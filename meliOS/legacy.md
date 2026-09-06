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

