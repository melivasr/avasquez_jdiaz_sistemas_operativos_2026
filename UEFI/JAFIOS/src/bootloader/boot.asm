;ASM x86 for a basic UEFI bootloader

bits 64 ; UEFI funciona en ambiente de 64
default rel ; direccionamiento relativo para UEFI x86-64

; Punto de entrada para que UEFI ejecute el programa 
global efi_main ; global hace visible al Linker

; ============================================================
; INICIO DEL BOOTLOADER 
; UEFI carga BOOTX64.EFI e inicia a ejecutar desde esta etiqueta
; ============================================================

efi_main: 
    mov rbx, rdx ; UEFI pone en RDX un puntero a EFI_SYSTEM_TABLE. 
    ; se conserva RBX  para acceder a ConOut -> llamar a OutputString.
    mov rax, [rbx + 64] ; EFI_SYSTEM_TABLE=bx contiene el puntero ConOut
    ; protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x40 (64 bytes).
    mov rcx, rax ; conservar puntero a ConOut en RCX
    mov rax, [rax + 8] ; EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
    ; el primer campo es Reset y el segundo es OutputString.
    mov rdx, msg ; OutputString recibe un puntero a una cadena UTF-16 (CHAR16)
    ; no una cadena ASCII. RDX es el 2do argumento de la función en x64 que utiliza UEFI.
    call rax
    jmp $ ; jump infinito TEMPORAL, BLOQUEA TODO

    xor eax, eax ; limpiar ax
    ret ; en UEFI, retorno = 0 representa EFI_SUCCESS

msg:
    dw 'H','e','l','l','o',' ','U','E','F','I','!',13,10,0