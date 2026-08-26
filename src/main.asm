;ASM x86 for a basic bootloader

org 0x7C00 ;Directiva NASM. Indica direccion de origen del codigo.
bits 16 ;Directiva NASM. Indica modo de ensamblado.
;Se inicia en 16 bits para retro-compatibilidad

; set up consistente del programa
main:
    mov ax, 0 ;cargar 0 en registro general de 16 bits
    mov ds, ax ;cargar 0 en el data segment
    mov es, ax ;0 en el extra segment
    mov ss, ax ;0 en el stack segment

    mov sp, 0x7C00 ;iniciar el stack despues de nuestra aplicacion
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

os_boot_msg: db 'JafiOS has booted', 0x0D, 0x0A, 0; 0 es para indicar el fin del string, hexas son new line characters 
    
; llenar los 510 bytes
rellenado:
    times 510-($-$$) db 0 ; Directivas NASM. times -> Repite datos, db -> define byte
    ; $ = pos actual dentro del codigo
    ; $$ = inicio de seccion actual (linea 0 del codigo)
    ; $-$$ = bytes dentro del codigo
    ; Entonces, se escribe el byte 0 un total de 510-bytes en el codigo
    ; Asi, se consigue rellenar de ceros y llegar a los ultimos 2 bytes 

; poner 55AA al final del MBR
firma:
    dw 0xAA55 ; Directiva NASM. Define word (32 bits)
    ; por ser little endian, se acomoda:
    ; 510: 0x55
    ; 511: 0xAA
    ; Asi, como el sector permitido por legacy (MBR) es de 512 bytes
    ; en los ultimos 2 bytes (510,511) va a encontrar el identificador 55AA