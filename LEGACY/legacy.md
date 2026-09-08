# Legacy 

Este documento describe las interrupciones BIOS utilizadas y el flujo de ejecución.

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

## 1.2 Cómo arranca una computadora 

Cuando la computadora se enciende, lo primero que ejecuta es la BIOS (Basic Input Output System). La BIOS inicializa el hardware básico y busca un dispositivo arrancable. En un arranque tipo legacy, la BIOS carga el primer sector del disco en la dirección de memoria 0x7C00.

Ese primer sector tiene exactamente 512 bytes. La BIOS revisa los últimos dos bytes de ese bloque buscando la firma 0xAA55. Si la encuentra, asume que ese sector es un bootloader válido y comienza a ejecutar el código desde la dirección 0x7C00.

Por eso, todo bootloader debe terminar con esa firma en la posición correcta. Si la firma no está presente, el sistema no considera que el disco sea arrancable.

### What is a Legacy BIOS?

 En legacy la BIOS es una implementación más antigua que carga un bootloader desde el disco antes de pasar el control al sistema operativo. 

## 1.3 El bootloader: boot.asm

El archivo `boot.asm` es el primer código que se ejecuta. Su objetivo es:

1. ubicarse en la dirección 0x7C00,
2. preparar el entorno mínimo del hardware,
3. leer el disco,
4. localizar el archivo del kernel,
5. cargarlo en memoria,
6. transferir el control al kernel.

Algunas instrucciones importantes son:

- `org 0x7C00`: indica al ensamblador que todo el código debe considerarse cargado en esa dirección de memoria, porque la BIOS lo va a ubicar ahí.
- `bits 16`: el procesador arranca en modo real de 16 bits por compatibilidad con hardware antiguo.
- `main`: es el punto de entrada del bootloader.
- `hlt`: pausa la CPU hasta que ocurra una interrupción.
- `jmp halt`: crea un bucle infinito de seguridad para evitar que el código siga ejecutándose fuera de control si se interrumpe.
- `times 510-($-$$) db 0`: rellena con ceros hasta completar 510 bytes del sector.
- `dw 0xAA55`: escribe la firma de arranque en los últimos dos bytes del sector.

## 1.4 El kernel principal: main.asm

Una vez que el bootloader ha cargado el kernel en memoria, el control pasa a `main.asm`. El kernel se encarga de la lógica del sistema operativo, como la interfaz del usuario, la gestión del reloj, el cronómetro y la alarma.

El flujo es:

1. la BIOS carga el bootloader,
2. el bootloader busca el kernel,
3. el kernel se carga en memoria,
4. el bootloader salta a la dirección del kernel,
5. el sistema operativo comienza a correr.

## 1.5 Uso del Makefile

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

## 3. Modos disponibles

El sistema cuenta con los siguientes modos principales:

- `Reloj`: muestra la hora actual y se actualiza por segundo.
- `Cronómetro`: mide el tiempo transcurrido y permite iniciar, pausar y reiniciar.
- `Alarma`: permite configurar una hora específica para activar la alerta del RTC.
- `Menú principal`: permite navegar entre los modos y volver al menú desde cualquiera de ellos.
- `Salir`: termina la ejecución del sistema.

Estos modos se seleccionan desde el menú interactivo y permiten cambiar entre funciones sin reiniciar el sistema.
