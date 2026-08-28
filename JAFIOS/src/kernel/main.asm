;ASM x86 for a basic kernel

org 0x0 ;Directiva NASM. Indica direccion de origen del codigo.
bits 16 ;Directiva NASM. Indica modo de ensamblado.
;Se inicia en 16 bits para retro-compatibilidad

; set up consistente del programa
start:
    mov si, os_boot_msg ; guardar en source index el msg
    call print
    call modoReloj
    hlt; congela cpu hasta que ocurra una interrupcion , por si hay no esperadas.

; bucle si ocurren interrupciones
halt_loop:
    hlt ;
    jmp halt_loop


; ==================================
; Funciones auxiliares
; ==================================

; ==================================
; Print
; ==================================
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

;
; ==================================
; Modo Reloj
; ==================================

modoReloj:
    mov si, time_msg
    call print

    mov ah, 02h ; INT 1AH = 02h lee RTC
    INT 1Ah ; devuelve la hora, minutos y segundos en formato BCD en ch, cl y dh respectivamente
    mov [segundo_actual], dh ; guardar segundo actual

    ; Imprimir Horas : HH = CH
    mov al, ch
    call printBCDTime
    mov al, ':'
    call printChar

    ; Imprimir Minutos : MM = CL
    mov al, cl
    call printBCDTime
    mov al, ':'
    call printChar

    ; Imprimir Segundos : SS = DH
    mov al, dh
    call printBCDTime
    mov al, ':'
    call printChar

    ; Imprimir new line
    mov si, new_line
    call print

    ; esperar a que cambie el segundo

esperar:
    mov ah, 02h ; leer RTC
    INT 1Ah ; devuelve CH, CL, DH, DL en BCD

    cmp dh, [segundo_actual] ; comparar el segundo actual
    je esperar ; sigue esperando si son iguales
    jmp modoReloj; si no son iguales, imprimimos otra vez

; ==================================
; PrintBCDTime
; Recibe un BCD en al y lo imprime correctamente.
; usa bcd_to_ascii y printChar
; Input: AL = BCD 
; ==================================
printBCDTime:
    call bcd_to_ascii ; Recibe BCD en AL, devuelve en AL decenas, en AH unidades
    
    ; Imprimir decenas
    push ax ; preservar unidades
    call printChar ; imprime AL
    pop ax ; recuperar unidades

    ; Imprimir unidades
    mov al, ah ; mover unidades a imprimir
    call printChar
    ret

;
; ==================================
; BCD
; Input: AL = BCD 
; Output: AL = decenas en ascii, AH = unidades en ascii
; ==================================
bcd_to_ascii:
    mov ah, al
    and ah, 0Fh ; unidades en binario
    add ah, '0' ; ascii

    shr al, 4 ; decenas en binario
    add al, '0' ; ascii
    ret

;
; ==================================
; Print Char
; Input: AL = char ascii a imprimir
; ==================================
printChar:
    mov ah, 0Eh ; for teletype output, recibe al = char ascii a imprimir, bh = pagina de vide
    xor bh, bh ; 0 en bh para monitor 0
    INT 10h ; Video interrupt
    ret

; ==================================
; VARIABLES
; ==================================
os_boot_msg: db 'JafiOS has booted', 0x0D, 0x0A, 0; 0 es para indicar el fin del string, hexas son new line characters 
time_msg: db 'Actual Time: ', 0x0D, 0x0A, 0; 
new_line: db 0x0D, 0x0A, 0;
segundo_actual: db 0
