ORG 0x0 ; Define el origen del código en la dirección 0x0000
BITS 16 ; Modo de 16 bits

; Inicialización del kernel
main:
    MOV AX, CS ; Guarda el segmento de código actual en AX
    MOV DS, AX ; Inicializa el segmento de datos con CS
    MOV ES, AX ; Inicializa ES con el mismo segmento

    MOV SI, os_boot_msg 
    CALL print 

    CALL print_time_loop ; Inicia el reloj RTC en pantalla

halt:
    CLI ; Deshabilita las interrupciones
    HLT ; Detiene la CPU hasta que ocurra una interrupción
    JMP halt; Mantiene el sistema detenido de forma indefinida


; Imprime una cadena terminada en 0
print: 
    PUSH SI
    PUSH AX
    PUSH BX

print_loop:
    LODSB ; Carga el siguiente carácter en AL y avanza SI
    OR AL, AL ; Comprueba si el carácter es el terminador nulo
    JZ print_done ; Si AL == 0, termina la cadena
    MOV AH, 0x0E ; Servicio BIOS para imprimir carácter en pantalla
    MOV BH, 0x00 
    INT 0x10  ; Invoca al BIOS para imprimir el carácter en AL
    JMP print_loop ; Continúa con el siguiente carácter

print_done: 
    ;Restauramos
    POP BX 
    POP AX 
    POP SI 
    RET 


; Función para imprimir un solo carácter usando BIOS
; Entrada: AL = carácter a imprimir
putchar:
    PUSH AX
    PUSH BX
    MOV AH, 0x0E
    MOV BH, 0x00
    INT 0x10
    POP BX
    POP AX
    RET


; Mueve el cursor a la posición (fila, columna)
; Fila: DH, Columna: DL
; En este caso se usa la línea 0, columna 0
set_cursor:
    PUSH AX
    PUSH BX
    PUSH DX
    MOV AH, 0x02 ; Función BIOS para posicionar el cursor
    MOV BH, 0x00 ; Página de video 0
    MOV DH, 0x00 ; Fila 0
    MOV DL, 0x00 ; Columna 0
    INT 0x10 ; Llama a BIOS para mover el cursor
    POP DX
    POP BX
    POP AX
    RET

; Limpia la línea actual con espacios para redibujar la hora
clear_line:
    PUSH AX
    PUSH CX
    MOV CX, 80; 80 caracteres por línea

clear_line_loop:
    MOV AL, ' ' ; Carga un espacio en AL
    CALL putchar ; Lo imprime en pantalla
    LOOP clear_line_loop ; Repite CX veces

    POP CX
    POP AX
    RET

; Convierte un byte BCD a ASCII y lo imprime
print_byte_ascii:
    PUSH AX
    PUSH BX

    MOV BL, AL ; Guarda el valor original en BL

    ; Imprime el dígito alto 
    MOV AL, BL
    SHR AL, 4
    AND AL, 0x0F
    ADD AL, '0'
    CALL putchar

    ; Imprime el dígito bajo 
    MOV AL, BL
    AND AL, 0x0F
    ADD AL, '0'
    CALL putchar

    POP BX
    POP AX
    RET

; Bucle que actualiza la hora cada vez que cambia el segundo
; Usa INT 1Ah / AH=02h para leer la hora del RTC
; CH = horas, CL = minutos, DH = segundos (formato BCD)

print_time_loop:
    MOV BL, 0xFF 

print_time_update:
    MOV AH, 02h
    INT 1Ah ; CH=horas, CL=minutos, DH=segundos (BCD)

    CMP DH, BL ; Compara el segundo actual con el anterior
    JE print_time_update ; Si sigue igual, espera el próximo cambio

    MOV BL, DH ; Guarda el segundo actual para comparar luego

    CALL set_cursor ; Posiciona el cursor al inicio de la línea
    CALL clear_line ; Borra la línea actual
    CALL set_cursor ; Regresa al inicio para redibujar

    MOV SI, hora_msg ; Carga el texto "Hora actual: "
    CALL print 

    MOV AL, CH ; Carga horas
    CALL print_byte_ascii
    MOV AL, ':' ; Imprime dos puntos
    CALL putchar

    MOV AL, CL ; Carga minutos
    CALL print_byte_ascii
    MOV AL, ':' ; Imprime dos puntos
    CALL putchar

    MOV AL, DH ; Carga segundos
    CALL print_byte_ascii

    JMP print_time_update ; Repite el bucle para seguir actualizando la hora


os_boot_msg:
    DB "meliOS is working...", 0x0D, 0x0A, 0 

hora_msg:
    DB "Hora actual: ", 0 ; Texto para la hora

new_line:
    DB 0x0D, 0x0A, 0 ; Salto de línea
