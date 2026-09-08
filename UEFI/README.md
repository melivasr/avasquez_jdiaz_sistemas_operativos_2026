# Tarea 1 - Reloj/Cronómetro con Alarma Booteable
## Jafet Díaz & Melissa Vásquez

## Chuletas

Set-Up en Linux

```bash
# verificar qemu
kvm-ok

#install qemu
sudo apt-get install qemu-system
```

Ya teniendo el archivo asm

```bash
# LEGACY 

# moverse a terminal (linux - Jafet)
cd Documentos/Repositorios/Operativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/JAFIOS

# moverse a terminal (mac - Jafet)
cd dev/Operativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/JAFIOS

# ejecutar
make

# emular con qemu
qemu-system-i386 -fda build/main.img

# emular con qemu en RTC local
qemu-system-i386 -fda build/main.img -rtc base=localtime

# UEFI

# moverse a terminal (mac - Jafet)
cd dev/Operativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/UEFI/JAFIOS

# moverse a terminal (linux - Jafet)
cd Documentos/Repositorios/Operativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/UEFI/JAFIOS

```

Para agregar discos

mcopy no viene con mkfs.fat. Es parte del paquete mtools, que proporciona herramientas para manipular sistemas de archivos FAT desde Linux.

```bash
# verificar
which mcopy

# si no, instalar
sudo apt install mtools

#limpiar files
rm -rf build/*

# ejecutar
make

# Emular con qemu
```
# Que es un boot loader?

Un boot loader es un programa responsable de realizar el arranque de un computador utilizando el System Firmware, mejor conocido como BIOS (Basic Input/Output System)

Hay dos metodos principales: BIOS Legacy Mode y UEFI BIOS. 

Legacy corresponde al metodo obsoleto compatible con el viejo IBM PC. Es el metodo mas lento pero mucho mas sencillo de entender. Es dependiente de la arquitectura de 16 bits y esta limitada a almacenamiento pequeno.

UEFI por otro lado es la version mas moderna sin esas limitaciones pero mucho mas complejo. 

## Que hace Legacy?
En Legacy, se busca el boot device y se carga en la direccion de mem `0x7C00`.

El BIOS entonces lee el primer sector de codigo cargado en memoria, el `Master Boot Record (MBR).` Esta seccion tiene que estar escrita en ensamblado de 16 bits. El BIOS agarra este bloque de codigo y lee 512 bytes. El BIOS busca un identificador al final del bloque, en los ultimos dos bytes: el hexadecimal `0xAA55`. Si lo encuentra, asume que el bloque de codigo que leyo es un codigo bootable.

### En emulacion

Usando QEMU, el disco bootable es el `Floppy Disk`. En cada sector, hay 512 bytes. Hay que usar varios sectores del disco para guardar el kernel y boot loader. 
Para eso, hay que:
1. Formatear el disco usando un formato facil de entender, acceder y usar.
2. Interactuar con el `file system` para cargarle data del disco.

Inicialmente, se usara el formato FAT 12. Es el mas sencillo, por aprendizaje se inicia con ese.
FAT 12 funciona de forma que espera un "header" con informacion dle formato en el disco. Sin esa info, no funcionara. Ese header debe programarse en el `boot.asm`. En resumen, este header tiene dos secciones principales de "parametros" a definir:
- `EBR (Extended Boot Record/Registro de Arranque Extendida)`: Estructura de datos que forma parte del sector de arranque o que sirve para enlazar particiones logicas dentro de una particion extendida
- `BDB/BPB (BIOS Parameter Block/Bloque de Parametros del BIOS)`: Es la tabla de datos fundamental situada al principio del sector de arranque (VBR) que define la geometria y la estructura interna del sistema de archivos. Indica al SO como leer el disco.

Ahora bien, el disco puede ser leido a traves de la `INT 13` de ASM, pero esta recibe formato `CHS (Cylinder, Head, Sector)`. El formato LBA (Logical Block Addressing) es bastante mas intuitivo, por lo que podemos hacer la transformacion CHS -> LBA.

CHS -> LBA puede hacerse con la fórmula:
```math
LBA = (C*TH*TS)+(H*TS)+(S-1)
```
dónde:
- C = Sector Cylinder Number
- TH = Total Headers on disk
- TS = Total Sections on disk
- H = Sector Head Number
- S = Sector's number

A su vez, estos valores se calculan de la siguiente forma:
```math
t = \frac{LBA}{sectorsPerTrack}
```

```math
s = (LBA\%sectorsPerTrack) + 1
```

```math
h = t \% numberOfHeads = \frac{LBA}{sectorsPerTrack} \% numberOfHeads
```

```math
c = \frac{t}{numberOfHeads} = \frac{\frac{LBA}{sectorsPerTrack}}{numberOfHeads}
```

Donde `t` es track, `s` es sector, `h` es head, `c` es cilindro. Note que se ocupa realizar módulo. Módulo no existe como tal en x86 sino que al realizar `div`, el cociente queda en `ax`, el residuo queda en `dx`. Módulo es el residuo de la división.

Asi, el proceso seria: generar `t` usando `div word [bdb_sector_per_track]`. Esto deja ax=t. Luego, si hacemos `dx + 1` obtenemos `s` que es el módulo + 1. Luego, usamos `ax` (que contiene `LBA/sectors_per_track`) y lo dividimos entre `number of heads`. Así, `h` (el residuo) queda en `dx` y `c` (el cociente) queda en `ax`. Despues hay que hacer acomodos para que queden en los registros que se requieren, lo cual se explica en la documentación interna de `boot.asm`

Ahora bien, en fat 12 el disco se diide en 4 segmentos

Reserved segment -> tiene un set size que esta definido por el header (`bdb_reserved_sectors`)
file allocation tables (fat) segments -> size esta dado por `bdb_sectors_per_fat` multiplicado por `bdb_fat_count`
Root directory segment -> top level directory del sistema. De ahi se puede llegar atodo (trees). Esta dado por la continuacion de los reserved y FAT. Es de 1 sector, entonces, por ejemplo; si reserved es 1 y FAT es 18, root esta en el 19.
Finalmente, el Data Segment = es los datos en los archivos

Se suele ir al root directory y de ahi se localiza el archivo a buscar (el kernel por ejemplo).
Luego, vamos al data segment y recuperamos los datos asociados con el archivo, dado que el root nos dara la ubicacion de los datos en ese directorio particular.

Por lo tanto, el primer paso es obtener el LBA del root directory.