;ASM x86 for a basic kernel

org 0x0 ;Directiva NASM. Indica direccion de origen del codigo.
bits 16 ;Directiva NASM. Indica modo de ensamblado.
;Se inicia en 16 bits para retro-compatibilidad

; set up consistente del programa
start:
    mov si, os_boot_msg ; guardar en source index el msg
    call print
    hlt; congela cpu hasta que ocurra una interrupcion , por si hay no esperadas.

; bucle si ocurren interrupciones
halt_loop:
    hlt ;
    jmp halt_loop

; loop para prints
print:
    push si ;guardar source index en el stack
    push ax
    push bx
print_loop:
    lodsb ;cargar (load) en la parte baja de ax (al) un byte (8bits) de el source index, un char
    ;si el char SI es 0, es el fin del string y dejamos de imprimir.
    or al, al ;si en al (parte baja) hay un 0, 0 or 0 = 0
    jz done_print ;salta si flag cero se levanta

    ;si NO es un cero, entonces es un char valido (no end of line)
    mov ah, 0x0E ; indicador de impresion en screen
    mov bh, 0 ; bh es el page number, es usado para multiples monitores.
    INT 0x10 ; VIDEO INTERRUPT, busca ax y bx y hace la rutina de impresion

    jmp print_loop ;seguir imprimiendo hasta encontrar cero

done_print:
    pop bx
    pop ax
    pop si

    ret

os_boot_msg: db 'JafiOS has booted', 0x0D, 0x0A, 0; 0 es para indicar el fin del string, hexas son new line characters 
