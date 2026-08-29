;ASM x86 for a basic kernel

; ============================================================================
; DATOS PREVIOS
; Se salta desde el boot.asm con jmp 2000h:0000h (ver variables al final)
; Direccion física = CS × 16 + IP = 0x8000 = 8000h
; Despues del salto:
; CS = 2000h = kernel load segment
; DS = 2000h
; ES = 2000h
; IP = 0000h
; dl, [ebr_drive_number] = numero de unidad de BIOS

;============================================================================

org 0x0 ;Directiva NASM. Indica direccion de origen del codigo.
bits 16 ;Directiva NASM. Indica modo de ensamblado.
;Se inicia en 16 bits para retro-compatibilidad

; set up consistente del programa
start:
    mov si, os_boot_msg ; guardar en source index el msg
    call print
    mov si, menu_msg
    call print

menu:
    ; INT 16h , 00h para esperar por tecla
    mov ah, 00h
    int 16h ; devuelve en AL ascii, en AH scan

    cmp al, 'r' ; modo reloj
    je modoReloj

    cmp al, 'a' ; modo alarma
    je modoAlarma
    
    jmp menu ; se mantiene en bucle hasta que el usuario presione tecla

; bucle si ocurren interrupciones
halt_loop:
    hlt ;
    jmp halt_loop


; 
; ==================================
; Funciones auxiliares
; ==================================

; ==================================
; Print (Strings)
; ==================================

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
; Modo Alarma
; ==================================

modoAlarma:
    call configurar_alarma
    ; imprimir
    jmp menu

;
; ==================================
; Configurar la alarma. 
; Retorna a ModoAlarma o jmp a Error
; ==================================

configurar_alarma:
	call install_alarm_handler
	; Configurar alarma a las 14:35:20
	mov ah, 06h
	mov ch, 14h
	mov cl, 35h
	mov dh, 20h
		
	int 1Ah ; BIOS configura la alarma y sigue con la siguiente instr.
	jc alarm_error ; MANEJAR ERRORES

    ret

;
; ==================================
; Instalar handler INT 4Ah
; ==================================

install_alarm_handler:
    pushf ; guardar flags
    cli ; desactivar interrupciones enmascarables

    push es ; preservar es

	xor ax, ax ; es lo mismo que mov ax, 0000h
	mov es, ax ; ES = 0000h
	
    ; Guardar vector anterior
    mov ax, [es:0128h]
	mov [old_4a_offset], ax ; preservar offset viejo

	mov ax, [es:012Ah]
	mov [old_4a_segment], ax ; preservar segmento viejo

    ; Instalar nuevo handler
	mov word [es:0128h], alarm_handler ; poner el offset nuevo en IVT
	mov word [es:012Ah], cs ; poner el segmento actual en IVT

    pop es ; recuperar es

    popf ; restaurar flags

    ret

;
; ==================================
; Handler INT 4Ah
; ==================================

alarm_handler:
    ; hacer algo SENCILLO (como levantar un bit)
    pusha
    mov byte [cs:alarm_triggered], 1
    popa
    
    iret ; como se llama desde una INT, hay que guardar FLAGS, CS, IP

;
; ==================================
; Alarm Error
; Usa print, ret a ModoAlarma
; ==================================

alarm_error:
    mov si, alarm_error_msg
    call print
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

; 
; ==================================
; Esperar que el segundo cambie
; ==================================
esperar:
    mov ah, 02h ; leer RTC
    INT 1Ah ; devuelve CH, CL, DH, DL en BCD

    cmp dh, [segundo_actual] ; comparar el segundo actual
    je esperar ; sigue esperando si son iguales
    jmp modoReloj; si no son iguales, imprimimos otra vez

; 
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
; BCD -> ASCII 
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

; 
; ==================================
; VARIABLES
; ==================================

os_boot_msg: db 'JafiOS has booted !', 0x0D, 0x0A, 0; 0 es para indicar el fin del string, hexas son new line characters 
menu_msg: db 'Presiona R para el Modo Reloj, A para el Modo Alarma!', 0x0D, 0x0A, 0

; imprimir tiempo
time_msg: db 'Actual Time: ', 0x0D, 0x0A, 0; 
new_line: db 0x0D, 0x0A, 0;

; actualizar cada segundo
segundo_actual: db 0

; alarma
alarm_error_msg: db 'Error: Ya existe una alarma | Fallo en RTC', 0x0D, 0x0A, 0
alarm_triggered: db 0 
old_4a_offset  dw 0
old_4a_segment dw 0
