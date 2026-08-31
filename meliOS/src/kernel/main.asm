ORG 0x0 ; Define el origen del código en la dirección 0x0000
BITS 16 ; Modo de 16 bits

; Inicialización del kernel
main:
    MOV AX, CS ; Guarda el segmento de código actual en AX
    MOV DS, AX ; Inicializa el segmento de datos con CS
    MOV ES, AX ; Inicializa ES con el mismo segmento

    MOV SI, os_boot_msg 
    CALL print 

    CALL menu_select_mode ; Muestra el menú y espera la seleccion del usuario

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
    MOV AH, 0x02 ; Función BIOS para posicionar el cursor
    MOV BH, 0x00 ; Página de video 0
    ; DH = fila, DL = columna, se pasan por registros antes de llamar
    INT 0x10 ; Llama a BIOS para mover el cursor
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


; Lee una tecla y la devuelve en AL usando la interrupción BIOS
; INT 16h / AH = 00h
read_key:
    MOV AH, 00h ; Obtiene una tecla del buffer del teclado
    INT 16h ; AL = carácter ASCII, AH = código de scan
    RET

; Convierte una letra minúscula a mayúscula
upper_case:
    CMP AL, 'a'
    JB upper_done
    CMP AL, 'z'
    JA upper_done
    SUB AL, 0x20

upper_done:
    RET

; Muestra el menú y espera la opción elegida
menu_select_mode:
    MOV SI, menu_msg
    CALL print

; Opciones posibles a elegir
menu_wait_key:
    CALL read_key
    CALL upper_case

    CMP AL, 'A'
    JE mode_alarm
    CMP AL, 'R'
    JE mode_clock
    CMP AL, 'C'
    JE mode_chronometer
    CMP AL, 'V'
    JE menu_select_mode

    MOV SI, invalid_msg
    CALL print
    JMP menu_wait_key

; Modo alarma
mode_alarm:
    MOV SI, alarm_msg
    CALL print
    JMP wait_for_v 

; Modo reloj
mode_clock:
    MOV SI, clock_msg
    CALL print
    CALL print_time_loop

; Modo chronometro
mode_chronometer:
    MOV SI, chrono_msg
    CALL print
    JMP wait_for_v

;Si el usuario presiona V, vuelve al menu

wait_for_v:
    CALL read_key
    CALL upper_case

    CMP AL, 'V'
    JE menu_select_mode

    JMP wait_for_v

; Bucle que actualiza la hora cada vez que cambia el segundo
; Usa INT 1Ah / AH=02h para leer la hora del RTC
; CH = horas, CL = minutos, DH = segundos (formato BCD)
print_time_loop:
    MOV BL, 0xFF 

print_time_update:
    MOV AH, 02h
    INT 1Ah ; CH=horas, CL=minutos, DH=segundos (BCD)

    CMP DH, BL ; Compara el segundo actual con el anterior
    JE check_for_v ; Si sigue igual, revisa si hay tecla antes de seguir

    MOV BL, DH ; Guarda el segundo actual para comparar luego

    MOV DH, 3 ; Fila donde se muestra la hora
    MOV DL, 0 ; Columna inicial de la línea
    CALL set_cursor ; Posiciona el cursor en la línea de la hora
    CALL clear_line ; Borra la línea actual
    MOV DH, 3 ; Regresa a la misma fila para redibujar
    MOV DL, 0
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

check_for_v:
    MOV AH, 01h ; INT 16h/AH=01h: comprueba si hay tecla en buffer
    INT 16h
    JZ print_time_update ; No hay tecla, continúa actualizando la hora

    MOV AH, 00h ; INT 16h/AH=00h: lee la tecla
    INT 16h
    CALL upper_case

    CMP AL, 'V'
    JE menu_select_mode

    JMP print_time_update ; Si no es V, sigue el reloj

;Mensajes para mostrar en pantalla
os_boot_msg:
    DB "meliOS is working...", 0x0D, 0x0A, 0 

menu_msg:
    DB 0x0D, 0x0A, "Seleccione modo: A=Alarma   R=Reloj   C=Cronometro   V=Volver al menu", 0x0D, 0x0A, 0

invalid_msg:
    DB 0x0D, 0x0A, "Opcion invalida. Presione A, R, C o V.", 0x0D, 0x0A, 0

alarm_msg:
    DB 0x0D, 0x0A, "Modo alarma activado.", 0x0D, 0x0A, 0

clock_msg:
    DB 0x0D, 0x0A, "Modo reloj activado.", 0x0D, 0x0A, 0

chrono_msg:
    DB 0x0D, 0x0A, "Modo cronometro activado.", 0x0D, 0x0A, 0

hora_msg:
    DB "Hora actual: ", 0 ; Texto para la hora

new_line:
    DB 0x0D, 0x0A, 0 ; Salto de línea
