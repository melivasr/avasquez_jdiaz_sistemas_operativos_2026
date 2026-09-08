# Legacy 

Este documento describe la ejecución, las interrupciones BIOS utilizadas y el flujo de cada modo del sistema operativo en 16 bits.

## 1. Descripción general

El proyecto es un SO minimalista pensado para arrancar desde una imagen FAT12 creada con `mkfs.fat`. El flujo del arranque es:

1. El bootloader carga el kernel desde el disco.
2. El kernel se ejecuta en modo de x86.
3. El usuario entra al modo interactivo con `I`.
4. El sistema presenta un menú y cada modo se ejecuta con bucles controlados por teclado y por las interrupciones BIOS.

Para compilar el proyecto:

```bash
cd ~/Documents/sistemasOperativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/meliOS
make clear
make
```

La ejecución  es desde la terminal del sistema, no desde el editor:

```bash
qemu-system-x86_64 -fda build/main.img -rtc base=localtime
```

> Importante: esto debe hacerse desde una terminal externa, fuera del entorno de VS Code.

## 2. Interrupciones BIOS principales utilizadas

El sistema hace uso de varias interrupciones del BIOS:

### 2.1 `INT 10h` - Video y cursor

Se usa para:

- imprimir texto con `AH = 0x0E`
- posicionar el cursor con `AH = 0x02`
- limpiar líneas y pantallas
- actualizar la salida visual de cada modo

### 2.2 `INT 16h` - Teclado

Se usa para:

- leer una tecla: `AH = 0x00`
- consultar si hay tecla disponible sin bloquear: `AH = 0x01`
- recibir la entrada del usuario para navegar por los menús y modos

### 2.3 `INT 1Ah` - RTC / reloj del sistema

Se usa para:

- leer la hora actual con `AH = 0x02`
- leer ticks del RTC con `AH = 0x00`
- configurar alarma del RTC con `AH = 0x06`
- desactivar alarma con `AH = 0x07`

### 2.4 `INT 4Ah` - handler personalizado de la alarma

El sistema reemplaza el vector de interrupción del RTC para la alarma y luego lo restaura con `restore_alarm_handler`.

Este flujo permite:

- detectar cuándo llega la hora programada
- mostrar la alarma visualmente
- mantener una lógica de cancelación con `X`

## 3. Flujo de ejecución 

### 3.1 Inicio del sistema

Cuando se arranca, se ejecuta `main`:

1. Se inicializa `DS` y `ES` con el segmento actual.
2. Se imprime la visualización inicial.
3. El sistema entra a `wait_start`.
4. Allí espera una tecla:
   - `I` entra al menú interactivo
   - `Q` apaga el sistema

## 4. Menú principal

El flujo principal del menú es:

1. `menu_select_mode`
2. `CALL clear_screen`
3. Se imprime el mensaje del menú
4. `menu_wait_key` espera una tecla sin bloquear
5. Se valida la opción:
   - `A` -> modo alarma
   - `H` -> reloj
   - `C` -> cronómetro
   - `R` -> reinicia cronómetro
   - `V` -> vuelve al menú
   - `X` -> cancela alarma
   - `Q` -> cierra el sistema

## 5. Modo reloj

Muestra la hora actual del sistema con actualización por segundo.

### Flujo

1. `mode_clock` pone `current_mode = 2`
2. Borra la pantalla
3. Imprime el mensaje del reloj
4. Llama a `print_time_loop`
5. `print_time_loop` hace lo siguiente:
   - llama a `chrono_update`
   - lee la hora con `INT 1Ah / AH = 02h`
   - compara si el segundo cambió
   - si cambió, vuelve a dibujar la hora
   - revisa si hay tecla presionada
6. Si la tecla es:
   - `V` -> vuelve al menú
   - `X` -> cancela alarma
   - `R` -> reinicia cronómetro
   - `S` -> alterna entre reloj y cronómetro
   - `Q` -> cierra el sistema

## 6. Modo cronómetro

Mide el tiempo transcurrido y lo muestra en pantalla.

### Flujo

1. `mode_chronometer` pone `current_mode = 3`
2. Inicializa el estado si es la primera vez
3. Muestra el mensaje del cronómetro y sus controles
4. Llama a `chrono_update`
5. Entra a `chrono_loop`:
   - actualiza el valor visible
   - consulta si hay una tecla
   - si la hay, lee y procesa:
     - `I` -> iniciar/reanudar
     - `P` -> pausar
     - `R` -> reiniciar
     - `S` -> alterna con reloj
     - `V` -> vuelve al menú
     - `X` -> cancela alarma
     - `Q` -> apaga

### Estado interno del cronómetro

Se usa una estructura de variables:

- `chrono_running`
- `chrono_start_low` / `chrono_start_high`
- `chrono_elapsed_low` / `chrono_elapsed_high`
- `chrono_last_seconds`

Esto permite que el tiempo siga corriendo aunque el usuario cambie de modo.

## 7. Modo alarma

Programa una hora de activación del RTC para que la alarma se active cuando la hora actual coincida con la configurada. Solo puede configurarse una alarma al momento.

### Flujo 

1. El usuario entra a `mode_alarm`.
2. `read_alarm_time` pide la hora en formato `HHMMSS`.
3. Se valida que:
   - horas entre `00` y `23`
   - minutos entre `00` y `59`
   - segundos entre `00` y `59`
4. Si la hora es válida, se guarda en:
   - `alarm_hour`
   - `alarm_minute`
   - `alarm_second`
5. Se instala el handler de alarma con `install_alarm_handler`.
6. Se arma el RTC con `INT 1Ah / AH = 06h`.
7. Se muestra el mensaje:
   - `Alarma configurada. Presione V para volver al menu.`
8. Se pasa a `alarm_set_wait`.
9. En ese bucle, el sistema espera una tecla:
   - `V` -> vuelve al menú
   - `X` -> cancela la alarma
   - `Q` -> apaga el sistema

### Cuando ejecuta la alarma

Cuando la hora actual coincide con la hora programada:

1. `check_alarm_state` llama a `check_alarm_time`
2. `INT 1Ah / AH = 02h` lee la hora actual
3. Si coincide, llama a `alarm_notify`
4. Se muestra el aviso:
   - `*** ALARMA ACTIVADA, presione X para cancelar ***`
5. La alarma queda activa hasta que se cancela con `X`

### Cancelación

`cancel_alarm` hace lo siguiente:

- limpia el aviso visual
- desactiva el estado de alarma
- ejecuta `INT 1Ah / AH = 07h` para desactivar la alarma del RTC
- restaura el vector original de la interrupción con `restore_alarm_handler`

