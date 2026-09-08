# Legacy 

Este documento describe la ejecución, las interrupciones BIOS utilizadas y el flujo de cada modo del sistema operativo en 16 bits.

## 1. Descripción general

El proyecto es un SO pensado para arrancar desde una imagen FAT12 creada con `mkfs.fat`. El flujo del arranque es:

1. El bootloader carga el kernel desde el disco.
2. El kernel se ejecuta en modo de x86.
3. El usuario entra al modo interactivo con `I`.
4. El sistema presenta un menú y cada modo se ejecuta dependiendo de lo que el usuario seleccione.

## 1.1 Requisitos previos

Es necesario tener instalados los siguientes programas:

- `qemu-system-x86_64`
- `nasm`

Estos deben estar disponibles en la terminal del sistema antes de ejecutar el proyecto.

## 1.2 Uso del Makefile

Desde la carpeta del proyecto se pueden usar los siguientes comandos:

```bash
cd ~/Documents/sistemasOperativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/LEGACY
make
make run
make clear
```

Descripción rápida:

- `make` compila el bootloader y el kernel, y genera la imagen `build/main.img`.
- `make run` genera la imagen y la ejecuta con QEMU.
- `make clear` elimina los artefactos generados en la carpeta `build`.

> Importante: esto debe hacerse desde una terminal externa, fuera del entorno de VS Code.

En caso de querer usar el equivalente desde el Makefile, también puedes ejecutar:

```bash
make run
```

Y la ejecución directa con QEMU queda como:

```bash
qemu-system-x86_64 -fda build/main.img -rtc base=localtime
```

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

