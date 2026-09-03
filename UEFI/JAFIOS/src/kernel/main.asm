; ASM x86 for a basic kernel

; Recibe punteros a:
; Runtime Services -> RCX
; ConOut Services -> RDX
bits 64 ; ambiente de 64 bits para UEFI
global kernel_main 

; ============================================================
; MACRO: convierte un string ASCII a CHAR16 (UTF-16) para UEFI
; ============================================================
%macro utf16str 1
    %strlen %%len %1
    %assign %%i 1
    %rep %%len
        %substr %%c %1 %%i
        dw %%c
        %assign %%i %%i+1
    %endrep
%endmacro

; ============================================================
; CONSTANTES UEFI
; ============================================================

EFI_TEXT_OUT_PROTOCOL_off equ 0x8 ; offset del servicio de OutputString desde ConOut
EFI_READ_KEY_PROTOCOL_off equ 0x8 ; offset del servicio de OutputString desde ConOut

; ============================================================
; START
; ============================================================

kernel_main:
    mov [rel runtime_addr], rcx
    mov [rel conout_addr], rdx
    mov [rel conin_addr], r8
    
    ; Boot
    lea rcx, [rel msg]
    call print

menu:
    ; Welcome
    lea rcx, [rel wel_msg]
    call print
    ; Menu MSG
    lea rcx, [rel menu_msg]
    call print
menu_loop:
    call read_key

    cmp ax, 'r'
    je modo_reloj

    jmp menu_loop


;
halt_loop:
    hlt
    jmp halt_loop

;
; ========================================================
; Modo_Reloj
; ========================================================

modo_reloj:
    call get_time
    

;
; ========================================================
; ReadKeyStroke. Utiliza la funcion 0x08 de ConIn Services
; RAX = Funct (offset 0x08)
; IN = This (RCX), puntero a key (RDX)
; Key + 2 = ascii leido
; Devuelve ascii en ax
; ========================================================

read_key:
    mov rcx, [rel conin_addr] ; this
    mov rax, [rcx + EFI_READ_KEY_PROTOCOL_off]

    lea rdx, [key]

    call rax

    mov ax, [key + 2] ; devolver ASCII es ax
    ret

;
; ========================================================
; Get time. Utiliza la funcion 0x00 de Runtime Services
; RAX = Funct Get Time (offset 0x00)
; IN = puntero a time (RCX), puntero a capabilities (RDX)
; ========================================================

get_time:
    mov rax, [rel runtime_addr]
    mov rcx, [rel time_pointer]

    ; Shadow space
    sub rsp, 32
    call rax
    ; Restaurar stack
    add rsp, 32

    ret

;
; ========================================================
; Print, utiliza de text output protocol su funcion 0x8
; RAX = TEXT OUTPUT PROTOCOL
; IN = This = ConOut (RCX), direccion de Msg (RDX)
; Protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x40 (64 bytes).
; ========================================================
print:
    mov rdx, rcx ; segundo argumento (msg) pasado por el caller en RCX
    mov rcx, [rel conout_addr]; This
    mov rax, [rcx + EFI_TEXT_OUT_PROTOCOL_off] ; call

    ; Shadow space
    sub rsp, 32
    ; ConOut->OutputString(ConOut, msg)
    call rax
    ; Restaurar stack
    add rsp, 32

    ret

;
; ============================================================
; VARIABLES
; ============================================================

msg:
    utf16str "Booting from UEFI..."
    dw 13, 10, 0

wel_msg:
    utf16str "Welcome to Jafi OS!"
    dw 13, 10, 0

menu_msg:
    utf16str "Opciones: R = Reloj, C = Cronometro, A = Alarma, E = Exit to boot"
    dw 13, 10, 0

; recibidos desde el bootloader
runtime_addr: dq 0;
conout_addr: dq 0;
conin_addr: dq 0;

; Usados por func
time_pointer: dq 0;
key_pointer: dq 0
