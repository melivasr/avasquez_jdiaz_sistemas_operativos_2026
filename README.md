# Tarea 1 - Reloj/Cronómetro con Alarma Booteable
## Jafet Díaz & Melissa Vásquez

## Chuletas

```bash
# moverse a terminal (jafi)
cd Documentos/Repositorios/Operativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026

# ejecutar
make

# emular con qemu
qemu-system-i386 -fda build/main.img
```

# Que es un boot loader?

Un boot loader es un programa responsable de realizar el arranque de un computador utilizando el System Firmware, mejor conocido como BIOS (Basic Input/Output System)

Hay dos metodos principales: BIOS Legacy Mode y UEFI BIOS. 

Legacy corresponde al metodo obsoleto compatible con el viejo IBM PC. Es el metodo mas lento pero mucho mas sencillo de entender. Es dependiente de la arquitectura de 16 bits y esta limitada a almacenamiento pequeno.

UEFI por otro lado es la version mas moderna sin esas limitaciones pero mucho mas complejo. 

## Que hace Legacy?
En Legacy, se busca el boot device y se carga en la direccion de mem `0x7C00`.

El BIOS entonces lee el primer sector de codigo cargado en memoria, el `Master Boot Record (MBR).` Esta seccion tiene que estar escrita en ensamblado de 16 bits. El BIOS agarra este bloque de codigo y lee 512 bytes. El BIOS busca un identificador al final del bloque, en los ultimos dos bytes: el hexadecimal `0xAA55`. Si lo encuentra, asume que el bloque de codigo que leyo es un codigo bootable
