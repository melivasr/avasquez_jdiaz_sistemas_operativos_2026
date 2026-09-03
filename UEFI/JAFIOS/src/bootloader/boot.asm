;ASM x86 for a basic UEFI bootloader

bits 64 ; UEFI funciona en ambiente de 64
default rel ; direccionamiento relativo para UEFI x86-64 

; ============================================================
; CONSTANTES UEFI
; ============================================================
EFI_SYSTEM_TABLE_BOOT_SERVICES equ 0x60 ; Offset a Boot Services 
EFI_SYSTEM_TABLE_RUNTIME_SERVICES equ 0x58 ; offset a Runtime Services
EFI_SYSTEM_TABLE_CON_OUT_SERVICES equ 0x40 ; offset a ConOut Services
EFI_SYSTEM_TABLE_CON_IN_SERVICES equ 0x30 ; offset a ConIn Services

EFI_LOCATE_PROTOCOL_off equ 0x140 ; FUNCTION FROM Boot Services

EFI_OPEN_VOLUME_off equ 0x8 ; FUNCTION FROM SIMPLE FS

; Offsets para funciones de root or other children (instancia de EFI_FILE_PROTOCOL)
EFI_FILE_OPEN_off equ 0x8 ; FUNCTION from File Protocol
EFI_FILE_READ_off equ 0x20 ; FUNCTION from File Protocol 

EFI_TEXT_OUT_PROTOCOL_off equ 0x8 ; offset del servicio de OutputString desde ConOut

; ============================================================
; GUID (Globally Unique Identifier) -> usado en Locate Protocol
; identificador de 128 bits (16 bytes) 
; de protocolos y estructuras en UEFI. 
; ============================================================

; GUID de FileSystem = 0964e5b22-6459-11d2-8e39-00a0c969723b
EFI_simple_fs_guid:
    dd 0964e5b22h
    dw 6459h
    dw 11d2h
    db 8eh, 39h, 00h, 0a0h, 0c9h, 69h, 72h, 3bh

;
; ============================================================
; INICIO DEL BOOTLOADER 
; UEFI carga BOOTX64.EFI e inicia a ejecutar desde esta etiqueta
; UEFI entrega la EFI_SYSTEM_TABLE en rdx
; ============================================================

; Punto de entrada para que UEFI ejecute el programa 
global efi_main ; global hace visible al Linker

efi_main: 
    mov rdi, rdx ; guardar puntero a SysTable en RDI

    ; Obtener RUNTIME SERVICES 
    mov rax, [rdi + EFI_SYSTEM_TABLE_RUNTIME_SERVICES]
    mov [rel runtime_info], rax ; guardar puntero a RUNTIME SERVICES en runtime_info
    
    ; Obtener ConOut Services
    mov rax, [rdi + EFI_SYSTEM_TABLE_CON_OUT_SERVICES]
    mov [rel conout_info], rax ; guardar puntero a CONOUT SERVICES en conout_info

    ; Obtener ConIn Services
    mov rax, [rdi + EFI_SYSTEM_TABLE_CON_IN_SERVICES]
    mov [rel conin_info], rax ; guardar puntero a CONOUT SERVICES en conout_info

    ; Obtener BOOT SERVICES
    mov rax, [rdi + EFI_SYSTEM_TABLE_BOOT_SERVICES] ; rax apunta a boot services

;
; ========================================================
; LOCATE PROTOCOL -> Obtener la interfaz Simple File 
; RAX = LOCATE PROTOCOL
; Input: RCX = GUID, RDX = REGISTRATION
; Output: R8 = INTERFACE
; ========================================================

locate_protocol:
    ; Preparar argumentos
    lea rcx, [rel EFI_simple_fs_guid] ; cargar guid del protocolo deseado
    xor edx, edx ; Registration = 0
    lea r8, [rel fs_protocol] ; Interfaz = &FS_Protocol (puntero)

    ; Obtener puntero a LocateProtocol
    mov rax, [rax + EFI_LOCATE_PROTOCOL_off] ; movernos en la tabla a LOCATE PROTOCOL

    sub rsp, 32 ; reserva 4x8=32 en el stack para los 4 args (shadow space reservation)
    call rax ; llamar a LOCATE PROTOCOL
    add rsp, 32 ; restaurar la pila

    ; Verificación
    cmp rax, 0 ; EFI_SUCCES = 0
    jne locate_error ; Si RAX != 0, no se pudo localizar el protocolo

    cmp qword [rel fs_protocol], 0 ; verificar que se haya cargado el protocolo
    je locate_error 

;
; ========================================================
; OPEN VOLUME -> Abrir root y otorgarle interfaz efi_file_protocol
; CALL / RETURN : OpenVolume offset = RAX
; IN: RCX = This (EFI_Simple_File_System_Protocol)
; OUT: RDX = &Root 
; ========================================================

open_volume:
    ; Obtener puntero a OpenVolume
    mov rax, [rel fs_protocol] ; rax = Simple File System protocol
    mov rax, [rax + EFI_OPEN_VOLUME_off] ; RAX = openVolume

    ; Preparar argumentos
    mov rcx, [rel fs_protocol] ; this
    lea rdx, [rel root]

    sub rsp, 32 ; reservar shadow space
    call rax
    add rsp, 32 ; restaurar shadow space

    ; Verificar Open Vplume
    cmp rax, 0 ; EFI_SUCCESS = 0
    jne volume_error

    cmp qword [rel root], 0 ; ver si la root cambia.
    je volume_error

;
; ========================================================
; OPEN FILE
; RCX = This, RDX = NewHandle (OUT), R8 = FileName, R9 = OpenMode
; Stack = Attributes
; OpenMode = EFI_FILE_MODE_READ = 0x0000000000000001
; Attributes = 0
; ========================================================

open_file:
    mov rax, [rel root] ; EFI FILE PROTOCOL = instancia root
    mov rcx, rax ; guardar EFI FILE PROTOCOL (THIS)

    lea rdx, [rel main_file] ; Vamos a abrir main.bin
    lea r8, [rel filename]
    mov r9, 1
    mov rax, [rax + EFI_FILE_OPEN_off] ; RAX = OpenFile 

    ; Atrributes en el stack
    sub rsp, 40 ; 32 de args + 8 de Attributes
    mov qword [rsp + 32], 0

    call rax 
    add rsp, 40

    ; Verificar que el archivo se abre
    cmp rax, 0
    jne file_error

    cmp qword [rel main_file], 0 ; puntero a main file cambia
    je file_error

    ; Inicio de la tabla
    mov rax, [rbx + EFI_SYSTEM_TABLE_BOOT_SERVICES] ; rax apunta a boot_services

;
; ========================================================
; READ FILE
; RCX = main_file. RDX = &main_size, R8 = & buffer hacia main
; ========================================================

read_file:
    mov rax, [rel main_file] 

    ; Preparar argumentos
    mov rcx, rax ; RCX = This
    lea rdx, [rel main_size]
    lea r8, [rel main_buffer]

    mov rax, [rax + EFI_FILE_READ_off] ; RAX = Read()

    sub rsp, 32 ; shadow space para los 4 args
    call rax
    add rsp, 32

    ; Verificar READ
    cmp rax, 0
    jne read_error ; EFI_SUCCESS

    cmp qword [rel main_size], 0 ; Verificar size esperado
    je read_error 

;
; ========================================================
; JUMP TO KERNEL
; En main_buffer se encuentra el puntero a main.asm
; Antes de saltar, hay que pasarle como "parametros"
; RCX = runtime_info
; RDX = conout_info
; RAX = &main_buffer
; ========================================================

mov rcx, [rel runtime_info]
mov rdx, [rel conout_info]
mov r8, [rel conin_info]
lea rax, [rel main_buffer] ; mov devolveria la primera instr
jmp rax

boot_end:
    ; RETORNAR A UEFI CON EXITO
    xor eax, eax ; limpiar ax
    ret ; en UEFI, retorno = 0 representa EFI_SUCCESS

;

; LOOP por si LOCATE PROTOCOL falla
locate_error:
    jmp boot_end

; LOOP por si OPEN VOLUME falla
volume_error:
    jmp boot_end

; LOOP por si OPEN FILE falla
file_error:
    jmp boot_end
; LOOP por si READ FILE falla
read_error:
    jmp boot_end

;
; ============================================================
; VARIABLES
; ============================================================

fs_protocol: dq 0 ; 8 bytes para puntero a FileSystem Protocol/Interface
root: dq 0 ; root pointer

filename: dw 'm','a','i','n','.','b','i','n',0
main_file: dq 0 ; main pointer
main_size: dq 4096 ; size maxima de main
main_buffer: times 4096 db 0 ; puntero a la dirección 0 del main

runtime_info: dq 0 ; Puntero a pasar al main.asm / kernel
conout_info: dq 0 ; Puntero a pasar al main.asm / kernel
conin_info: dq 0 ; Puntero a pasar al main.asm / kernel

