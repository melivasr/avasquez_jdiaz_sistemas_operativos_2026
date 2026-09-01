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

; Limpia una línea con espacios
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

; Limpia la pantalla completa reutilizando clear_line.
; Se posiciona en cada fila y borra la línea completa antes de continuar.
clear_screen:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV CX, 25 ; 25 filas en modo texto estándar
    MOV DH, 0

clear_screen_loop:
    MOV DL, 0 ; Columna inicial de la fila
    CALL set_cursor
    CALL clear_line ; Borra la línea actual usando la función base
    INC DH ; Siguiente fila
    LOOP clear_screen_loop

    MOV DH, 0
    MOV DL, 0
    CALL set_cursor ; Devuelve el cursor al inicio

    POP DX
    POP CX
    POP BX
    POP AX
    RET

; Muestra un mensaje en la fila indicada
show_row:
    PUSH SI
    MOV DL, 0
    CALL set_cursor
    CALL clear_line
    MOV DL, 0
    CALL set_cursor
    POP SI
    CALL print
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
    CALL clear_screen
    MOV DH, 0 ;Posicion en pantalla
    MOV SI, menu_msg
    CALL show_row

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

    MOV DH, 1 ;Posicion donde se imprime
    MOV SI, invalid_msg
    CALL show_row
    JMP menu_wait_key

; Modo alarma
mode_alarm:
    MOV DH, 1 ;Posicion donde se imprime
    MOV SI, alarm_msg
    CALL show_row
    JMP wait_for_v 

; Modo reloj
mode_clock:
    MOV DH, 1 ;Posicion donde se imprime
    MOV SI, clock_msg
    CALL show_row
    CALL print_time_loop

; Modo chronometro
mode_chronometer:
    ; Inicializa el cronómetro en estado pausado y con tiempo acumulado = 0.
    ; chrono_running = 0  -> cronometro detenido
    ; chrono_elapsed_low/high = 0 -> tiempo acumulado = 0
    XOR AX, AX
    MOV [chrono_running], AL
    MOV [chrono_elapsed_low], AX
    MOV [chrono_elapsed_high], AX
    ; Fuerza el primer dibujo del tiempo como 00:00:00.
    MOV AX, 0FFFFh
    MOV [chrono_last_seconds], AX
    ; Muestra el título y las instrucciones del cronómetro.
    MOV DH, 1 ;Posicion donde se imprime
    MOV SI, chrono_msg
    CALL show_row
    MOV DH, 2
    MOV SI, chrono_controls_msg
    CALL show_row
    CALL chrono_update

chrono_loop:
    ; Actualiza el valor visible del cronómetro en cada iteración.
    CALL chrono_update

    ; Consulta si hay una tecla presionada sin bloquear el conteo.
    MOV AH, 01h
    INT 16h
    JZ chrono_loop

    ; Si hubo tecla, la lee, si es minuscula se pasa a mayúscula.
    MOV AH, 00h
    INT 16h
    CALL upper_case

    ; Comandos del cronómetro:
    ; I = iniciar/reanudar, P = pausar, R = reiniciar, V = volver al menú.
    CMP AL, 'I'
    JE chrono_start
    CMP AL, 'P'
    JE chrono_pause
    CMP AL, 'R'
    JE chrono_reset
    CMP AL, 'V'
    JE menu_select_mode
    JMP chrono_loop

chrono_start:
    MOV AL, [chrono_running]
    CMP AL, 1
    JE chrono_loop
    ; Guarda el tick actual del BIOS para usarlo como referencia.
    ; Luego, cada actualización de tiempo restará este valor
    ; al tick actual para obtener el intervalo transcurrido.
    CALL get_bios_ticks
    MOV [chrono_start_high], CX
    MOV [chrono_start_low], DX
    ; Activa el cronómetro.
    MOV AL, 1
    MOV [chrono_running], AL
    JMP chrono_loop

chrono_pause:
    ; Si el cronómetro ya está detenido, no hay nada que pausar.
    ; chrono_running = 0 => parado, chrono_running = 1 => corriendo.
    MOV AL, [chrono_running]
    OR AL, AL
    JE chrono_loop

    ; Antes de detenerlo, guardamos el tiempo transcurrido desde el último inicio
    CALL chrono_current_interval

    ; Después de guardar el intervalo, marcamos el cronómetro como detenido.
    ; Esto evita que siga sumando tiempo mientras está pausado.
    XOR AX, AX
    MOV [chrono_running], AL

    ; Forzamos una actualización de la pantalla para que el último valor visible
    ; sea redibujado inmediatamente al pausar.
    MOV AX, 0FFFFh
    MOV [chrono_last_seconds], AX
    JMP chrono_loop

chrono_reset:
    ; Reinicia el cronómetro a cero.
    ; Primero borramos el tiempo acumulado guardado en chrono_elapsed_low/high.
    XOR AX, AX
    MOV [chrono_elapsed_low], AX
    MOV [chrono_elapsed_high], AX

    ; Se fuerza la actualización de la pantalla para que el cronómetro muestre 00:00:00
    ; aunque el cronómetro se estaba mostrando en otro valor antes del reinicio.
    MOV AX, 0FFFFh
    MOV [chrono_last_seconds], AX

    ; Si el cronómetro estaba corriendo, se redefine el punto de inicio para que
    ; el tiempo nuevo comience a contar desde este instante exacto.
    MOV AL, [chrono_running]
    OR AL, AL
    JE chrono_loop
    CALL get_bios_ticks
    MOV [chrono_start_high], CX
    MOV [chrono_start_low], DX
    JMP chrono_loop

;Si el usuario presiona V, vuelve al menu

wait_for_v:
    CALL read_key
    CALL upper_case

    CMP AL, 'V'
    JE menu_select_mode

    JMP wait_for_v

; Lee el contador de ticks desde medianoche: CX:DX.
; INT 1Ah / AH=00h devuelve la hora del sistema en ticks del RTC,
; medidos desde la medianoche. La pareja CX:DX representa un contador
; de 32 bits; CX es la parte alta y DX la parte baja.
; Este valor se usa para medir intervalos de tiempo en el cronómetro.
get_bios_ticks:
    MOV AH, 00h
    INT 1Ah
    RET

; Acumula el tiempo transcurrido desde la última reanudación.
; El cronómetro guarda dos cantidades:
;   - chrono_start_low/high: tick del BIOS en el momento de iniciar/reanudar
;   - chrono_elapsed_low/high: tiempo total ya medido antes de este instante
; El intervalo actual se calcula como:
;   intervalo = ticks_actuales - ticks_inicio
; y luego se suma a chrono_elapsed.
chrono_current_interval:
    ; Lee el tick actual del BIOS.
    ; INT 1Ah/AH=00h devuelve CX:DX = contador de ticks desde medianoche.
    CALL get_bios_ticks
    ; Resta el punto de inicio para obtener cuántos ticks han pasado
    ; desde que se activó o reanudó el cronómetro.
    SUB DX, [chrono_start_low]
    SBB CX, [chrono_start_high]
    ADD [chrono_elapsed_low], DX
    ADC [chrono_elapsed_high], CX
    RET

; Actualiza el valor mostrado solo al cambiar el segundo.
chrono_update:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    ; Parte del tiempo acumulado durante pausas anteriores.
    MOV DX, [chrono_elapsed_low]
    MOV CX, [chrono_elapsed_high]
    MOV AL, [chrono_running]
    OR AL, AL
    JE chrono_convert_values
    ; Si corre, añade ticks_actuales - ticks_de_inicio.
    PUSH CX
    PUSH DX
    CALL get_bios_ticks
    ; CX:DX queda con el intervalo que está corriendo ahora.
    SUB DX, [chrono_start_low]
    SBB CX, [chrono_start_high] ;Resta el tiempo de inicio para obtener el intervalo actual
    POP BX  ; Recupera la parte baja acumulada.
    ADD DX, BX
    POP BX  ; Recupera la parte alta acumulada.
    ADC CX, BX ;Suma el acarreo a la parte alta.

chrono_convert_values:
    ;El tiempo acumulado viene en ticks del BIOS.
    ;Como 1 segundo ≈ 18 ticks, la fórmula es:
    ;segundos = total_ticks / 18
    ;(se usa DIV para hacer la división entera).
    MOV AX, DX
    MOV DX, CX
    MOV BX, 18
    DIV BX  ; AX = segundos transcurridos.

    ;Si el valor de segundos no cambió, no hay que redibujar.
    CMP AX, [chrono_last_seconds]
    JE chrono_update_done
    MOV [chrono_last_seconds], AX

    ;Ahora convertimos el total de segundos a horas/minutos/segundos:
    ;horas = segundos_totales / 3600
    ;resto = segundos_totales % 3600
    XOR DX, DX
    MOV BX, 3600
    DIV BX ; AX = horas, DX = resto (segundos restantes).
    MOV [chrono_hours], AL

    ;minutos = resto / 60
    ;segundos = resto % 60
    MOV AX, DX
    XOR DX, DX
    MOV BX, 60
    DIV BX ; AX = minutos, DX = segundos.
    MOV [chrono_minutes], AL
    MOV [chrono_seconds], DL

    ;Muestra/ imprime HH:MM:SS.
    MOV DH, 4
    MOV SI, chrono_time_msg
    CALL show_row
    MOV AL, [chrono_hours]
    CALL print_byte_decimal
    MOV AL, ':'
    CALL putchar
    MOV AL, [chrono_minutes]
    CALL print_byte_decimal
    MOV AL, ':'
    CALL putchar
    MOV AL, [chrono_seconds]
    CALL print_byte_decimal

;Restaura registros y retorna
chrono_update_done:
    POP DX
    POP CX
    POP BX
    POP AX
    RET

; Imprime AL (0..99) como dos dígitos decimales.
; por ejemplo segundos/minutos/horas del cronómetro.
print_byte_decimal:
    PUSH AX
    PUSH BX
    ; AL = valor decimal a imprimir, máximo 99.
    ; Se convierte a dos cifras decimales: decenas y unidades.
    XOR AH, AH ; AH = 0 para que AX = AL.
    MOV BL, 10
    DIV BL ; AL = cociente (decenas), AH = resto (unidades).

    ; Imprime la cifra de las decenas.
    ADD AL, '0'
    CALL putchar

    ; Imprime la cifra de las unidades.
    MOV AL, AH
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
    MOV BH, DH ; Guarda los segundos en BH antes de cambiar DH por la fila

    CMP BH, BL ; Compara el segundo actual con el anterior
    JE check_for_v ; Si sigue igual, revisa si hay tecla antes de seguir

    MOV BL, BH ; Guarda el segundo actual para comparar luego

    MOV DH, 2 ;Posicion donde se imprime 
    MOV SI, hora_msg
    CALL show_row

    MOV AL, CH ; Carga horas
    CALL print_byte_ascii
    MOV AL, ':' ; Imprime dos puntos
    CALL putchar

    MOV AL, CL ; Carga minutos
    CALL print_byte_ascii
    MOV AL, ':' ; Imprime dos puntos
    CALL putchar

    MOV AL, BH ; Carga segundos guardados
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
os_boot_msg: DB "meliOS is working...", 0x0D, 0x0A, 0 
menu_msg: DB 0x0D, 0x0A, "Seleccione modo: A=Alarma  R=Reloj  C=Cronometro", 0x0D, 0x0A, 0
invalid_msg: DB 0x0D, 0x0A, "Opcion invalida. Presione A, R, C o V.", 0x0D, 0x0A, 0
alarm_msg: DB 0x0D, 0x0A, "Modo alarma activado, presione V para volver al menu", 0x0D, 0x0A, 0
clock_msg: DB 0x0D, 0x0A, "Modo reloj activado, presione V para volver al menu", 0x0D, 0x0A, 0

chrono_msg: DB "Modo cronometro", 0
chrono_controls_msg: DB "I=Iniciar/Reanudar  P=Pausar  R=Reiniciar  V=Volver", 0
chrono_time_msg: DB "Tiempo: ", 0
hora_msg: DB "Hora actual: ", 0 ; Texto para la hora
new_line: DB 0x0D, 0x0A, 0 ; Salto de línea

chrono_running: DB 0
chrono_start_low: DW 0
chrono_start_high: DW 0
chrono_elapsed_low: DW 0
chrono_elapsed_high: DW 0
chrono_last_seconds: DW 0
chrono_hours: DB 0
chrono_minutes: DB 0
chrono_seconds: DB 0
