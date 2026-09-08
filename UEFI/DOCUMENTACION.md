# UEFI BOOTLOADER

```
JAFIOS/
│
├── Makefile
│
├── src/
│   ├── bootloader/
│   │   └── boot.asm
│   │
│   └── kernel/
│       └── main.asm
│
└── build/
    ├── disk.img
    └── EFI/
        └── BOOT/
            └── BOOTX64.EFI
```

# Legacy BIOS vs. UEFI

- Legacy BIOS se basaba en un bootloader de 512 bytes que la BIOS carga en una dirección específica (`0x7C00`). 
- UEFI es un firmware que inicializa el hardware y es capaz de entender una partición FAT y buscar un ejecutable `.EFI` con formato `PE/COFF`.

Por lo tanto, en UEFI el flujo es:
1. UEFI Firmware busca el ejecutable `.EFI`.
2. En `EFI/BOOT/BOOTX64.EFI` se ejecuta el programa.
3. El bootloader UEFI en ejecución utiliza servicios UEFI (del `EFI_SYSTEM_TABLE`) para cargar el Kernel en RAM.

## \EFI\BOOT\BOOTX64.EFI

Es el resultado de compilar el ensamblador `boot.asm` a un `boot.o` usando `NASM` y luego enlazarlo (`ld`). El archivo generado `.EFI` es un ejecutable en formato `PE32+`. Cuando se hace el arranque del computador, UEFI Firmware carga este ejecutable y entra a la funcion `efi_main`. Al entrar, UEFI proporciona informacion, por ejemplo:
- `RCX = ImageHandler`
- `RDX = EFI_SYSTEM_TABLE`

## Preparar la USB en Linux

```bash
# Para montar una USB con nombre sda1
sudo mount /dev/sda1 /mnt/usb

# Verificar, deberia salir /mnt/usb
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS /dev/sda                   

# Copiar BOOTX64.EFI 
# - Cambiar la ruta del .EFI segun se necesite
sudo cp /home/jafi21/Documentos/Repositorios/Operativos/tarea1/avasquez_jdiaz_sistemas_operativos_2026/UEFI/JAFIOS/build/EFI/BOOT/BOOTX64.EFI /mnt/usb/EFI/BOOT/

# Verificar la copia
ls -lh /mnt/usb/EFI/BOOT/BOOTX64.EFI

# Copiar main.bin al USB
sudo cp build/main.bin /mnt/usb/main.bin

# Confirmar
ls -lh /mnt/usb/main.bin

# Confirmacion final de archivos
ls -l /mnt/usb

# Sincronizar la copia de los datos con el USB
sudo sync

# Desmontar la USB (retiro seguro)
sudo umount /mnt/usb

```



