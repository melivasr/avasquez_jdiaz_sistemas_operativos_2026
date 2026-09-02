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

; ============================================================
; START
; ============================================================

kernel_main:
    mov [rel runtime_addr], rcx
    mov [rel conout_addr], rdx 

    ; Boot
    lea rcx, [rel msg]
    call print

    ; Welcome
    lea rcx, [rel wel_msg]
    call print

menu:
    lea rcx, [rel menu_msg]
    call print

halt_loop:
    hlt
    jmp halt_loop

; ========================================================
; Print, utiliza de text output protocol su funcion 0x8
; RAX = TEXT OUTPUT PROTOCOL
; IN = This = ConOut (RCX), Msg (RDX)
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
