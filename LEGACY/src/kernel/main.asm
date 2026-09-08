ORG 0x0 ; Define el origen del código en la dirección 0x0000
BITS 16 ; Modo de 16 bits

; -----------------------------------------------------------------------------
; Entrada del kernel
; -----------------------------------------------------------------------------
; Inicialización del kernel
main:
    MOV AX, CS ; Guarda el segmento de código actual en AX
    MOV DS, AX ; Inicializa el segmento de datos con CS
    MOV ES, AX ; Inicializa ES con el mismo segmento

    MOV SI, os_boot_msg 
    CALL print 

    MOV SI, start_msg; inicio del programa
    CALL print

wait_start:
    CALL read_key
    CALL upper_case

    CMP AL, 'Q' ; Q => apaga el sistema desde cualquier punto
    JE halt

    CMP AL, 'I' ;entra al modo interactivo
    JE menu_select_mode

    JMP wait_start


halt:
    MOV DX, 0x604  ; puerto ACPI de apagado que usa QEMU
    MOV AX, 0x2000 ; valor que dispara el shutdown
    OUT DX, AX
    ; si por algún motivo no cerró, cae en halt y queda en un bucle infinito.
    CLI
    HLT
    JMP halt

; -----------------------------------------------------------------------------
; Salida de consola
; -----------------------------------------------------------------------------
; Imprime una cadena terminada en 0
print: 
    PUSH SI
    PUSH AX
    PUSH BX

print_loop:
    LODSB ; Carga el siguiente carácter en AL y avanza SI
    OR AL, AL ; Comprueba si el carácter es el terminador nulo
    JZ print_done ; Si AL == 0, termina la cadena
    ; INT 10h / AH=0Eh: imprime un carácter en la consola de texto.
    ; Se usa para mostrar cada byte de la cadena en la pantalla del BIOS.
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


; -----------------------------------------------------------------------------
; Salida de caracteres
; -----------------------------------------------------------------------------
; Función para imprimir un solo carácter usando BIOS
; Entrada: AL = carácter a imprimir
putchar:
    PUSH AX
    PUSH BX
    ; INT 10h / AH=0Eh: escribe un solo carácter en modo texto.
    ; Se usa para imprimir dígitos, signos y mensajes cortos sin recorrer cadenas.
    MOV AH, 0x0E
    MOV BH, 0x00
    INT 0x10
    POP BX
    POP AX
    RET

; -----------------------------------------------------------------------------
; Utilidades de pantalla
; -----------------------------------------------------------------------------
; Mueve el cursor a la posición (fila, columna)
; Fila: DH, Columna: DL
; En este caso se usa la línea 0, columna 0
set_cursor:
    PUSH AX
    PUSH BX
    ; INT 10h / AH=02h: coloca el cursor en una fila y columna dadas.
    ; Se usa para escribir mensajes en posiciones exactas de la pantalla.
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

; -----------------------------------------------------------------------------
; Visualización numérica
; -----------------------------------------------------------------------------
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
    ; INT 16h / AH=00h: lee una tecla del teclado y la devuelve en AL.
    ; Es la interrupción principal para capturar entrada del usuario.
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
; -----------------------------------------------------------------------------
; Interfaz de usuario
; -----------------------------------------------------------------------------
; Muestra el menú y espera la opción elegida
menu_select_mode:
    MOV BYTE [current_mode], 0
    CALL clear_screen
    MOV DH, 0 ;Posicion en pantalla
    MOV SI, menu_msg
    CALL show_row

; Opciones posibles a elegir
menu_wait_key:
    CALL check_alarm_state
    CALL chrono_update

    ; INT 16h / AH=01h: consulta si hay una tecla en el buffer sin bloquear.
    ; Si no hay entrada, el programa sigue ejecutando la lógica del menú.
    MOV AH, 01h ; Consulta si hay una tecla sin bloquear la cuenta del cronómetro.
    INT 16h
    JZ menu_wait_key

    ; INT 16h / AH=00h: lee la tecla presionada y la devuelve en AL.
    ; Permite procesar la opción elegida por el usuario.
    MOV AH, 00h
    INT 16h
    CALL upper_case

    CMP AL, 'Q' ; Q => apaga el sistema desde cualquier punto
    JE halt

    CMP AL, 'A'
    JE mode_alarm
    CMP AL, 'H'
    JE mode_clock
    CMP AL, 'C'
    JE mode_chronometer
    CMP AL, 'R'
    JNE menu_check_v
    CALL reset_chrono_global
    JMP menu_wait_key

menu_check_v:    
    CMP AL, 'V'
    JE menu_select_mode
    CMP AL, 'X'
    JE cancel_alarm_from_menu

    MOV DH, 1 ;Posicion donde se imprime
    MOV SI, invalid_msg
    CALL show_row
    JMP menu_wait_key

cancel_alarm_from_menu:
    CALL cancel_alarm
    JMP menu_wait_key

switch_clock_chrono:
    CALL clear_screen
    CMP BYTE [current_mode], 2
    JE mode_chronometer
    JMP mode_clock
; -----------------------------------------------------------------------------
; Modo alarma y flujo
; -----------------------------------------------------------------------------
; Modo alarma
; Pide la hora HHMMSS, la arma en el RTC y deja la alarma activa 
mode_alarm:
    MOV BYTE [current_mode], 1
    CALL clear_screen
    CALL read_alarm_time
    JC menu_select_mode

    ; Limpia el estado previo para que una alarma vieja no siga bloqueando la
    ; siguiente programación.
    MOV BYTE [alarm_triggered], 0 ; reinicia flag previo
    MOV BYTE [alarm_active], 0 ; limpia estado activo 

    ; Configura la alarma en el RTC usando AH=06h.
    ; El RTC toma HH/MM/SS desde CH/CL/DH y dispara la interrupción INT 4Ah
    ; cuando llega la hora programada. Si ya hay una alarma activa, la BIOS
    ; devuelve CF=1 y hay que salir con un mensaje de error.
    CALL install_alarm_handler ; reemplaza el vector de INT 4Ah con nuestro handler
    MOV BYTE [alarm_triggered], 0 ; marca que aún no se ha ejecutado la alarma
    MOV BYTE [alarm_active], 1 

    MOV CH, [alarm_hour] ; CH = hora programada
    MOV CL, [alarm_minute] ; CL = minuto programado
    MOV DH, [alarm_second] ; DH = segundo programado
    ; INT 1Ah / AH=06h: configura la alarma del RTC con HH/MM/SS.
    ; Cuando el reloj llega a ese instante, el hardware dispara la interrupción INT 4Ah.
    MOV AH, 06h ; AH=06h => programar alarma del RTC
    INT 1Ah ; BIOS RTC: configura alarma con CH/CL/DH
    JC alarm_error ; si falla, vuelve al menú con error

    MOV DH, 3
    MOV SI, alarm_set_msg
    CALL show_row
    JMP alarm_set_wait

alarm_set_wait:
    CALL check_alarm_state

    MOV AH, 01h
    INT 16h
    JZ alarm_set_wait

    MOV AH, 00h
    INT 16h
    CALL upper_case
    CMP AL, 'Q'
    JE halt
    CMP AL, 'V'
    JE menu_select_mode
    CMP AL, 'X'
    JNE alarm_set_wait
    CALL cancel_alarm
    JMP menu_select_mode

alarm_cancel_only:
    CALL cancel_alarm
    RET

alarm_read_reset:
    CALL reset_chrono_global
    JMP alarm_read

; Comprueba si la alarma ya llegó a la hora programada.
; Si coincide, muestra la notificación y espera la tecla de cancelación.
check_alarm_state:
    CMP BYTE [alarm_active], 1 ; si no hay alarma activa, no hace nada
    JE check_alarm_time
    RET

check_alarm_time:
    ; INT 1Ah / AH=02h: obtiene la hora actual del RTC.
    ; Esta comparación permite decidir si la alarma ya debe activarse.
    MOV AH, 02h ; AH=02h => leer hora actual del RTC
    INT 1Ah ; CH=horas, CL=minutos, DH=segundos

    CMP CH, [alarm_hour] ;compara hora actual con la hora programada
    JNE check_alarm_done
    CMP CL, [alarm_minute] ;compara minutos
    JNE check_alarm_done
    CMP DH, [alarm_second] ;compara segundos
    JNE check_alarm_done

    CALL alarm_notify ; cuando coincide, dispara la notificación visual
    RET

check_alarm_done:
    RET

; Limpia la línea donde se muestra el mensaje de la alarma
clear_alarm_line:
    PUSH AX
    PUSH DX
    MOV DH, 5 ; fila 5 = línea del aviso de alarma
    MOV DL, 0 ; columna 0
    CALL set_cursor ; ubica cursor en la línea del mensaje
    CALL clear_line ; limpia la fila completa para ocultar la alarma
    POP DX
    POP AX
    RET

; Se llama en cada actualización de tiempo. Si la alarma está sonando,
; alterna el color de toda la pantalla cada ~medio segundo para crear
; el efecto de parpadeo.
alarm_flash_update:
    CMP BYTE [alarm_triggered], 1 ; Si la alarma ocurrio, no se hace el efecto visual
    JE alarm_flash ; Entra al parpadeo solo cuando la alarma está activa
    RET

alarm_flash:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    CALL get_bios_ticks ; como ~18 ticks = 1 segundo, 9 ticks ≈ medio segundo.
    MOV AX, DX 
    MOV BX, 9 ; ~9 ticks por cambio de color, aprox. medio segundo
    XOR DX, DX ; Borra DX para preparar la división: AX / BX
    DIV BX ; AL = cociente, AH = resto; usamos el cociente para pulsar cada medio segundo
    AND AX, 1 ; Alterna 0/1 para cambiar de estado de color cada ciclo

    CMP AL, [alarm_color_state] ; Si el estado ya coincide, no hay que repintar
    JE alarm_flash_update_done ; mismo estado, no hay que redibujar
    MOV [alarm_color_state], AL ; Guarda el nuevo estado de color del parpadeo
    CALL alarm_paint_screen ; Pinta la pantalla con el nuevo color

alarm_flash_update_done:
    POP DX
    POP CX
    POP BX
    POP AX
    RET

; Pinta toda la pantalla con uno de dos colores según AL (0 o 1).
; Solo cambia el byte de atributo de cada celda, no el carácter.
alarm_paint_screen:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DI
    PUSH ES

    CMP AL, 0 ; Estado 0 = fondo azul
    JE alarm_paint_color_a ; Selecciona el primer esquema de color
    MOV BL, 0x4F ; blanco sobre rojo: color 2 para el parpadeo activo
    JMP alarm_paint_apply
alarm_paint_color_a:
    MOV BL, 0x1F ; blanco sobre azul: color 1 para el parpadeo activo

alarm_paint_apply:
    MOV AX, [video_mem_base] ; Segmento de memoria de video en modo texto VGA
    MOV ES, AX ; ES apunta a la memoria de pantalla
    XOR DI, DI ; DI = 0; empieza en la esquina superior izquierda
    MOV CX, [screen_cells] ; Total de celdas visibles de la pantalla en modo texto

alarm_paint_loop:
    MOV [ES:DI+1], BL ; Escribe el atributo de color en cada celda
    ADD DI, 2 ; Cada celda en modo texto ocupa 2 bytes: carácter + atributo
    LOOP alarm_paint_loop

    POP ES
    POP DI
    POP CX
    POP BX
    POP AX
    RET

; Restaura los colores normales (blanco sobre negro) al cancelar la alarma
; y reinicia el estado de parpadeo para la proxima alarma.
alarm_flash_reset:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DI
    PUSH ES

    MOV AX, [video_mem_base] ; Memoria de video en modo texto
    MOV ES, AX ; ES apunta a la VRAM
    XOR DI, DI ; Comienza en la esquina superior izquierda
    MOV CX, [screen_cells] ; Recorre todas las celdas visibles de la pantalla
    MOV BL, 0x07 ; Blanco sobre negro: color base por defecto del BIOS

alarm_flash_reset_loop:
    MOV [ES:DI+1], BL ; Restaura el atributo de cada celda
    ADD DI, 2 ; Cada celda ocupa 2 bytes en memoria de video
    LOOP alarm_flash_reset_loop

    MOV BYTE [alarm_color_state], 0FFh ; Fuerza un cambio al siguiente parpadeo

    POP ES
    POP DI
    POP CX
    POP BX
    POP AX
    RET

cancel_alarm:
    CMP BYTE [alarm_active], 1 ; Solo cancela si la alarma está activa
    JNE cancel_alarm_done ; Si no está activa, no hace nada

    CALL alarm_flash_reset ; Restaura el color normal de la pantalla antes de limpiar

    CALL clear_alarm_line ; Borra el aviso visible de alarma
    MOV BYTE [alarm_active], 0 ; Desactiva el flag global para dejarla inactiva
    MOV BYTE [alarm_triggered], 0 ; Limpia el disparo previo para la próxima alarma
    ; INT 1Ah / AH=07h: desactiva la alarma del RTC y deja libre el hardware.
    MOV AH, 07h ; AH=07h => desactivar alarma del RTC
    INT 1Ah ; BIOS RTC: desarma la alarma programada
    CALL restore_alarm_handler ; Vuelve al handler original del sistema

cancel_alarm_done:
    RET

; Muestra la alarma 
; La cancelación se hace con la tecla X
; Imprime el aviso una sola vez 
alarm_notify:
    CMP BYTE [alarm_triggered], 1
    JE alarm_notify_done
    MOV BYTE [alarm_triggered], 1
    MOV DH, 5
    MOV SI, alarm_ring_msg
    CALL show_row
alarm_notify_done:
    RET

alarm_error:
    ; Si la alarma no pudo configurarse, se quita el vector propio y se muestra
    ; un mensaje de error para volver al menú principal.
    CALL restore_alarm_handler
    MOV DH, 4
    MOV SI, alarm_invalid_msg
    CALL show_row
    JMP menu_select_mode

; -----------------------------------------------------------------------------
; Interrupción de alarma RTC
; -----------------------------------------------------------------------------
; Instala el handler de la alarma del RTC en INT 4Ah.
; El vector de interrupción 4Ah está en la IVT en offsets 0128h/012Ah.
; Guardamos el valor anterior para poder restaurarlo al salir del modo alarma.
install_alarm_handler:
    PUSHF
    CLI
    PUSH ES
    PUSH AX

    XOR AX, AX
    MOV ES, AX ; ES = 0000h => apuntamos a la IVT(tabla de vectores de interrupcion)

    MOV AX, [ES:0128h] ; guarda offset anterior de INT 4Ah
    MOV [old_offset], AX
    MOV AX, [ES:012Ah] ; guarda segmento anterior de INT 4Ah
    MOV [old_segment], AX

    MOV WORD [ES:0128h], alarm_handler ; instala nuestro handler en offset 0128h
    MOV WORD [ES:012Ah], CS ; instala segmento del código actual en 012Ah

    POP AX
    POP ES
    POPF
    RET

; Restaura el vector del BIOS al abandonar el modo alarma. 
restore_alarm_handler:
    PUSHF
    CLI
    PUSH ES
    PUSH AX

    XOR AX, AX
    MOV ES, AX ; ES = 0000h => apuntamos a la IVT (tabla de vectores de interrupcion)

    ; Recupera el vector original que había en INT 4Ah para dejar el sistema en
    ; el estado anterior a nuestra instalación del handler de alarma.
    MOV AX, [old_offset] ; carga el offset original de INT 4Ah desde la variable guardada
    MOV [ES:0128h], AX ; escribe ese offset en la entrada de la IVT para restaurar el handler

    MOV AX, [old_segment] ; carga el segmento original de INT 4Ah desde la variable guardada
    MOV [ES:012Ah], AX ; escribe ese segmento en la misma entrada para restaurar el vector completo

    POP AX
    POP ES
    POPF
    RET

; Handler ejecutado por IRQ8/INT 4Ah cuando el RTC dispara la alarma.
; Se ejecuta como un servicio del hardware en respuesta a la alarma del RTC.
; Aquí se marca la alarma como activada y se imprime el mensaje de aviso.
alarm_handler:
    ; Salvamos los registros que vamos a tocar para no corromper el estado de la
    ; tarea que estaba ejecutándose cuando llegó la interrupción.
    PUSH AX
    PUSH DX
    PUSH SI
    PUSH DS
    PUSH CS
    POP DS

    CMP BYTE [alarm_triggered], 1 ; ¿ya se había mostrado el aviso de esta alarma?
    JE alarm_handler_done ; si ya estaba, no reimprime el mensaje
    MOV DH, 5 ; línea reservada para el aviso de alarma
    MOV SI, alarm_ring_msg        
    CALL show_row             
    MOV BYTE [alarm_triggered], 1  ; marca la alarma ejecutada

    ; alarm_triggered = 1 permite que el bucle principal salga del HLT y termine
    ; la rutina de espera de la alarma.
    MOV BYTE [alarm_triggered], 1 ; marca que la alarma ya disparó para el flujo principal

alarm_handler_done:
    POP DS
    POP SI
    POP DX
    POP AX
    IRET
; -----------------------------------------------------------------------------
; Reloj y cronómetro
; -----------------------------------------------------------------------------
; Modo reloj
mode_clock:
    MOV BYTE [current_mode], 2
    CALL clear_screen
    ; Se imprime solo la hora y las instrucciones del modo reloj.
    MOV DH, 3
    MOV SI, clock_msg
    CALL show_row
    CALL print_time_loop

; Modo chronometro
mode_chronometer:
    MOV BYTE [current_mode], 3
    CALL clear_screen
    ; Solo se inicializa la primera vez que entra al cronómetro.
    ; Si ya existía un estado previo, se conserva para que siga contando.
    CMP BYTE [chrono_initialized], 1
    JE chrono_enter_ready

    XOR AX, AX
    MOV [chrono_running], AL
    MOV [chrono_elapsed_low], AX
    MOV [chrono_elapsed_high], AX
    MOV [chrono_start_low], AX
    MOV [chrono_start_high], AX
    MOV BYTE [chrono_initialized], 1

chrono_enter_ready:
    ; Fuerza el primer dibujo del tiempo como 00:00:00 cuando se entra por primera vez.
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

    CMP AL, 'Q'; Q => apaga el sistema
    JE halt

    ; Comandos del cronómetro:
    ; I = iniciar/reanudar, P = pausar, R = reiniciar, V = volver al menú,
    ; X = cancelar alarma activa si existe.
    CMP AL, 'I'
    JE chrono_start
    CMP AL, 'P'
    JE chrono_pause
    CMP AL, 'R'
    JNE chrono_check_v
    CALL reset_chrono_global
    JMP chrono_loop
chrono_check_v:
    CMP AL, 'V'
    JE menu_select_mode
    CMP AL, 'X'
    JNE chrono_check_s
    CALL cancel_alarm
    JMP chrono_loop
chrono_check_s:
    CMP AL, 'S'
    JE switch_clock_chrono
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

reset_chrono_global:
    ; Reinicia el cronómetro a cero y lo vuelve a arrancar desde el tiempo actual.
    XOR AX, AX
    MOV [chrono_elapsed_low], AX
    MOV [chrono_elapsed_high], AX
    MOV [chrono_start_low], AX
    MOV [chrono_start_high], AX
    MOV [chrono_running], AL
    MOV AX, 0FFFFh
    MOV [chrono_last_seconds], AX
    CALL get_bios_ticks
    MOV [chrono_start_high], CX
    MOV [chrono_start_low], DX
    MOV AL, 1
    MOV [chrono_running], AL
    MOV BYTE [chrono_initialized], 1
    RET

; Lee el contador de ticks desde medianoche: CX:DX.
; INT 1Ah / AH=00h devuelve la hora del sistema en ticks del RTC,
; medidos desde la medianoche. La pareja CX:DX representa un contador
; de 32 bits; CX es la parte alta y DX la parte baja.
; Este valor se usa para medir intervalos de tiempo en el cronómetro.
get_bios_ticks:
    ; INT 1Ah / AH=00h: devuelve el contador de ticks del sistema desde medianoche.
    ; Se usa como base para medir tiempos del cronómetro y del parpadeo.
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

    CALL alarm_flash_update 
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

    ; Solo se imprime si el usuario está en el modo cronómetro.
    ; El cronómetro continúa corriendo aunque el usuario cambie de modo.
    CMP BYTE [current_mode], 3
    JNE chrono_update_done

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

; -----------------------------------------------------------------------------
; Configuración de alarma
; -----------------------------------------------------------------------------
; Lee HHMMSS y guarda la hora como BCD para compararla con INT 1Ah/AH=02h.
; El usuario ingresa seis dígitos; la rutina valida HH/MM/SS. 
read_alarm_time:
    MOV DH, 1
    MOV SI, alarm_msg
    CALL show_row
    MOV DH, 2
    MOV SI, alarm_hora_msg
    CALL show_row
    XOR BX, BX

; Lee caracteres de teclado hasta completar 6 dígitos.
; Si no es un dígito entre 0 y 9, se descarta y se vuelve a pedir.
alarm_read:
    CALL read_key  
    CALL upper_case  

    CMP AL, 'Q'                 
    JE halt                     

    CMP AL, 'V'                 
    JE alarm_config_exit_to_menu ;
    CMP AL, 'X'                 
    JE alarm_cancel_only        
    CMP AL, 'R'                 
    JE alarm_read_reset          
    CMP AL, '0'  ; Verifica que el carácter esté en el rango numérico.
    JB alarm_read ; Si es menor que '0', ignora y vuelve a leer.
    CMP AL, '9' ; Verifica que el carácter sea un dígito.
    JA alarm_read ; Si es mayor que '9', ignora y vuelve a leer.
    CMP BL, 6  ; Comprueba si ya se ingresaron 6 dígitos.
    JNB alarm_read  ; Si ya hay 6, ignora y vuelve a leer.

    CALL putchar ; Muestra el dígito ingresado en pantalla.
    SUB AL, '0'  ; Convierte el carácter ASCII a su valor numérico.
    MOV [alarm_digits + BX], AL ; Guarda el dígito en la posición actual del arreglo.
    INC BL     ; Avanza al siguiente índice del arreglo.
    CMP BL, 6  ; Comprueba si ya se completaron los 6 dígitos.
    JB alarm_read  ; Si faltan dígitos, sigue pidiendo más.

    ; HH debe estar entre 00 y 23; MM y SS entre 00 y 59.
    ; Se valida primero la hora y luego los minutos/segundos.
    CMP byte [alarm_digits], 2  ; Comprueba la primera cifra de la hora (horas decenas).
    JA alarm_invalid   ; Si es mayor que 2, la hora es inválida.
    JNE alarm_check_minutes   ; Si la decena no es 2, salta a validar minutos.
    CMP byte [alarm_digits + 1], 3 ; Comprueba la segunda cifra de la hora (horas unidades).
    JA alarm_invalid    ; Si es mayor que 3, la hora es inválida.

alarm_check_minutes:
    CMP byte [alarm_digits + 2], 5 ; Comprueba la decena de minutos.
    JA alarm_invalid     ; Si es mayor que 5, los minutos son inválidos.
    CMP byte [alarm_digits + 4], 5 ; Comprueba la decena de segundos.
    JA alarm_invalid  ; Si es mayor que 5, los segundos son inválidos.

    ; Arma el valor final en formato BCD: HH, MM y SS.
    MOV AL, [alarm_digits]  ; Carga la primera cifra (hora decenas).
    SHL AL, 4  ; Desplaza al nibble alto del byte de horas.
    OR AL, [alarm_digits + 1]  ; Combina con la cifra de las unidades de hora.
    MOV [alarm_hour], AL ; Guarda la hora en BCD en alarm_hour.
    MOV AL, [alarm_digits + 2]  ; Carga la primera cifra de los minutos.
    SHL AL, 4 ; Desplaza al nibble alto del byte de minutos.
    OR AL, [alarm_digits + 3] ; Combina con la cifra de las unidades de minutos.
    MOV [alarm_minute], AL ; Guarda los minutos en BCD en alarm_minute.
    MOV AL, [alarm_digits + 4]  ; Carga la primera cifra de los segundos.
    SHL AL, 4 ; Desplaza al nibble alto del byte de segundos.
    OR AL, [alarm_digits + 5] ; Combina con la cifra de las unidades de segundos.
    MOV [alarm_second], AL ; Guarda los segundos en BCD en alarm_second.
    RET  ; Retorna con la hora de alarma

alarm_invalid:
    MOV DH, 4
    MOV SI, alarm_invalid_msg
    CALL show_row
    ; Vuelve a solicitar la hora de la alarma para reingresar un valor válido.
    JMP read_alarm_time

alarm_config_exit_to_menu:
    JMP menu_select_mode

; Bucle que actualiza la hora cada vez que cambia el segundo
; Usa INT 1Ah / AH=02h para leer la hora del RTC
; CH = horas, CL = minutos, DH = segundos (formato BCD)
print_time_loop:
    MOV BL, 0xFF 

print_time_update:
    CALL chrono_update
    ; INT 1Ah / AH=02h: lee la hora actual del RTC en formato BCD.
    ; Aquí se usa para actualizar la hora visible en la pantalla.
    MOV AH, 02h
    INT 1Ah ; CH=horas, CL=minutos, DH=segundos (BCD)
    MOV BH, DH ; Guarda los segundos en BH antes de cambiar DH por la fila

    CMP BH, BL ; Compara el segundo actual con el anterior
    JE check_for_v ; Si sigue igual, revisa si hay tecla antes de seguir

    MOV BL, BH ; Guarda el segundo actual para comparar luego

    MOV DH, 2 ; Fila de la hora actual
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

    CMP AL, 'Q' ; Q => apaga el sistema
    JE halt

    CMP AL, 'V'
    JE menu_select_mode
    CMP AL, 'X'
    JNE time_check_r
    CALL cancel_alarm
    JMP print_time_update
time_check_r:
    CMP AL, 'R'
    JNE time_check_s
    CALL reset_chrono_global
    JMP print_time_update
time_check_s:
    CMP AL, 'S'
    JE switch_clock_chrono
    JMP print_time_update ; Si no es V ni X ni R ni S, sigue el reloj

; -----------------------------------------------------------------------------
; Mensajes y estado
; -----------------------------------------------------------------------------
; Mensajes principales del sistema
os_boot_msg: DB "meliOS is working...", 0x0D, 0x0A, 0 
start_msg: DB 'Bienvenido al sistema, para entrar en modo interactivo presione la tecla "I", para cerrar presione "Q".', 0x0D, 0x0A, 0
menu_msg: DB 0x0D, 0x0A, "Seleccione modo: A=Alarma  H=Hora Actual  C=Cronometro R=Reiniciar cronometro Q=Cerrar", 0x0D, 0x0A, 0
invalid_msg: DB 0x0D, 0x0A, "Opcion invalida. Presione A=Alarma, H=Hora Actual, C=Cronometro o V.", 0x0D, 0x0A, 0

; Mensajes del modo alarma
alarm_msg: DB "Modo alarma: presione X para cancelar o V para volver al menu", 0
alarm_hora_msg: DB "Hora de alarma (HHMMSS): ", 0
alarm_invalid_msg: DB "Hora invalida. Use un valor entre 000000 y 235959.", 0
alarm_set_msg: DB "Alarma configurada. Presione V para volver al menu.", 0
alarm_ring_msg: DB "*** ALARMA ACTIVADA, presione X para cancelar ***", 0

; Mensajes del reloj y cronómetro
chrono_msg: DB "Modo cronometro", 0
chrono_controls_msg: DB "I=Iniciar/Reanudar P=Pausar R=Reiniciar S=Switch V=Volver" , 0
chrono_time_msg: DB "Tiempo: ", 0
hora_msg: DB "Modo reloj. Hora actual: ", 0 ; Texto para la hora
clock_msg: DB "Presione S para cambiar entre reloj y cronometro. R para reiniciar el cronometro y V para volver al menu", 0 ; Texto para la hora

; Estado global del kernel
current_mode: DB 0 ; Modo activo actual: reloj, alarma o cronómetro
chrono_initialized: DB 0 ; Indica si el cronómetro ya fue inicializado
alarm_triggered: DB 0 ; Marca si la alarma ya disparó
alarm_active: DB 0 ; Indica si la alarma está armada y activa
old_offset: DW 0 ; Offset del handler original de INT 4Ah
old_segment: DW 0 ; Segmento del handler original de INT 4Ah

; Configuración de la alarma
alarm_hour: DB 0 ; Hora programada para la alarma
alarm_minute: DB 0 ; Minuto programado para la alarma
alarm_second: DB 0 ; Segundo programado para la alarma
alarm_digits: TIMES 6 DB 0 ; Digitos capturados HHMMSS
alarm_color_state: DB 0FFh ; Estado del parpadeo visual de la alarma
video_mem_base: DW 0xB800 ; Segmento de memoria de video en modo texto VGA
screen_cells: DW 80 * 25 ; Total de celdas de texto del modo VGA (80x25)

; Estado del cronómetro
chrono_running: DB 0 ; 1 si el cronómetro está corriendo
chrono_start_low: DW 0 ; Parte baja del tick inicial del cronómetro
chrono_start_high: DW 0 ; Parte alta del tick inicial del cronómetro
chrono_elapsed_low: DW 0 ; Tiempo acumulado bajo del cronómetro
chrono_elapsed_high: DW 0 ; Tiempo acumulado alto del cronómetro
chrono_last_seconds: DW 0 ; Último segundo visualizado en pantalla
chrono_hours: DB 0 ; Horas mostradas del cronómetro
chrono_minutes: DB 0 ; Minutos mostrados del cronómetro
chrono_seconds: DB 0 ; Segundos mostrados del cronómetro
