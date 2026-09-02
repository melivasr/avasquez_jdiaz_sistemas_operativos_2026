; ASM x86 for a basic kernel

; Recibe punteros a:
; Runtime Services -> RCX
; ConOut Services -> RDX
bits 64 ; ambiente de 64 bits para UEFI
global kernel_main 

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

    ; ========================================================
    ; TEXT OUTPUT PROTOCOL
    ; RAX = TEXT OUTPUT CHAR-16 (word)
    ; Hay que moverse a ConOut desde la sys table
    ; Protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x40 (64 bytes).
    ; ========================================================
    mov rax, [rdx + EFI_TEXT_OUT_PROTOCOL_off] ; aún contiene conout
    ; Segundo argumento = cadena UTF-16
    lea rdx, [rel msg]
    ; Shadow space
    sub rsp, 32
    ; ConOut->OutputString(ConOut, msg)
    call rax
    ; Restaurar stack
    add rsp, 32

    hlt


; ============================================================
; VARIABLES
; ============================================================

msg: dw 'Welcome to UEFI Jafi OS!',13,10,0

runtime_addr: dq 0;
conout_addr: dq 0;
