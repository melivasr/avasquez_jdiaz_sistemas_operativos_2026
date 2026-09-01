;ASM x86 for a basic UEFI bootloader

bits 64 ; UEFI funciona en ambiente de 64
default rel ; direccionamiento relativo para UEFI x86-64 

; ============================================================
; CONSTANTES DE TABLA UEFI
; En ConOut = 0x4 = Reset, 0x8 = OutputString.
; ============================================================
EFI_SYSTEM_TABLE_BOOT_SERVICES equ 0x60 ; TABLA GENERAL
EFI_LOCATE_PROTOCOL_off equ 0x140 ; offset del servicio de LOCATE PROTOCOL

EFI_OPEN_VOLUME_off equ 0x8 ; offset para abrir volumen desde LOCATE PROTOCOL

; Offsets dentro de Open Volumel en root
EFI_FILE_OPEN_off equ 0x8
EFI_FILE_READ_off equ 0x20

EFI_ConOut_off equ 0x40 ; offset a ConOut
EFI_TEXT_OUT_PROTOCOL_off equ 0x8 ; offset del servicio de OutputString desde ConOut

; ============================================================
; GUID (Globally Unique Identifier)
; identificador de 128 bits (16 bytes) 
; de protocolos y estructuras en UEFI.
; ============================================================

; GUID de FileSystem = 0964e5b22-6459-11d2-8e39-00a0c969723b
EFI_simple_fs_guid:
    dd 0964e5b22h
    dw 6459h
    dw 11d2h
    db 8eh, 39h, 00h, 0a0h, 0c9h, 69h, 72h, 3bh

; ============================================================
; INICIO DEL BOOTLOADER 
; UEFI carga BOOTX64.EFI e inicia a ejecutar desde esta etiqueta
; ============================================================

; Punto de entrada para que UEFI ejecute el programa 
global efi_main ; global hace visible al Linker

efi_main: 
    mov rdi, rdx ; UEFI pone en RDX un puntero a EFI_SYSTEM_TABLE. 
    ; se conserva RBX  para acceder a ConOut -> llamar a OutputString.

    ; Inicio de la tabla
    mov rax, [rdi + EFI_SYSTEM_TABLE_BOOT_SERVICES] ; rax apunta a boot services

    ; Preparar LOCATE PROTOCOL 
    ; RAX = LOCATE PROTOCOL
    ; Input: RCX = GUID, RDX = REGISTRATION
    ; Output: R8 = INTERFACE
    lea rcx, [rel EFI_simple_fs_guid] ; rcx apunta a GUID de FS (lea carga direccion)
    xor edx, edx ; Registration = 0
    lea r8, [rel fs_protocol] ; Interfaz = &FS_Protocol (puntero)
    mov rax, [rax + EFI_LOCATE_PROTOCOL_off] ; movernos en la tabla a LOCATE PROTOCOL
    sub rsp, 32 ; reserva 4x4=32 en el stack para los 4 args (shadow space reservation)
    call rax ; llamar a LOCATE PROTOCOL
    add rsp, 32 ; restaurar la pila

    cmp rax, 0 ; EFI_SUCCES = 0
    jne locate_error ; Si RAX != 0, no se pudo localizar el protocolo

    cmp qword [rel fs_protocol], 0 ; verificar que se haya cargado el protocolo
    je locate_error 

    ; ========================================================
    ; OPEN VOLUME
    ; ========================================================

    ; Obtener puntero a OpenVolume
    mov rax, [rel fs_protocol] ; rax = FS protocol
    mov rax, [rax + EFI_OPEN_VOLUME_off] ; RAX = openVolume

    ; RAX = Open volume tiene:
    ; RCX = fs_protocol, RDX = direccion donde guardar root
    mov rcx, [rel fs_protocol]
    lea rdx, [rel root]
    sub rsp, 32 ; reservar shadow space
    call rax
    add rsp, 32 ; restaurar shadow space

    ; Verificar Open Vplume
    cmp rax, 0 ; EFI_SUCCESS = 0
    jne volume_error

    cmp qword [rel root], 0 ; ver si la root cambia.
    je volume_error

    ; ========================================================
    ; OPEN FILE
    ; RCX = This, RDX = NewHandle, R8 = FileName, R9 = OpenMode
    ; Stack = Attributes
    ; OpenMode = EFI_FILE_MODE_READ = 0x0000000000000001
    ; Attributes = 0
    ; ========================================================

    mov rax, [rel root] ; EFI FILE PROTOCOL
    mov rcx, rax ; guardar EFI FILE PROTOCOL (THIS)

    lea rdx, [rel main_file]
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

    ; ========================================================
    ; READ FILE
    ; RCX = main_file. RDX = &main_size, R8  = buffer para F4
    ; ========================================================

    mov rax, [rel main_file] 
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

    cmp qword [rel main_size], 1 ; Verificar size esperado
    jne read_error 

    cmp byte [rel main_buffer], 0xF4 ; comprombar halt
    jne read_error

    ; ========================================================
    ; TEXT OUTPUT PROTOCOL
    ; RAX = TEXT OUTPUT CHAR-16 (word)
    ; Hay que moverse a ConOut
    ; Protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x40 (64 bytes).
    ; ========================================================
    ; EFI_SYSTEM_TABLE + 0x40 = ConOut
    mov rcx, [rdi + EFI_ConOut_off]
    ; ConOut + 0x08 = OutputString
    mov rax, [rcx + EFI_TEXT_OUT_PROTOCOL_off]
    ; Segundo argumento = cadena UTF-16
    lea rdx, [rel msg]
    ; Shadow space
    sub rsp, 32
    ; ConOut->OutputString(ConOut, msg)
    call rax
    ; Restaurar stack
    add rsp, 32

    ; RETORNAR A UEFI CON EXITO
    xor eax, eax ; limpiar ax
    ret ; en UEFI, retorno = 0 representa EFI_SUCCESS

;
boot_end:
;

; LOOP por si no sirve el LOCATE PROTOCOL
locate_error:
    jmp locate_error

; LOOP por si OPEN VOLUME falla
volume_error:
    jmp volume_error

; LOOP por si OPEN FILE falla
file_error:
    jmp file_error

read_error:
    jmp read_error

;
; ============================================================
; VARIABLES
; ============================================================

msg: dw 'H','e','l','l','o',' ','U','E','F','I','!',13,10,0

; Open Main
filename: dw 'm','a','i','n','.','b','i','n',0

; FS
fs_protocol: dq 0 ; 8 bytes para puntero al FileSystem
root: dq 0 ; direccion para root
main_file: dq 0 ; puntero a main
main_size: dq 1 ; size of main
main_buffer: times 4096 db 0 ; buffer para recibir el size de main