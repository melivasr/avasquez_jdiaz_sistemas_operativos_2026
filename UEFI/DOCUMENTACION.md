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

## Legacy BIOS vs. UEFI

- Legacy BIOS se basaba en un bootloader de 512 bytes que la BIOS carga en una dirección específica (`0x7C00`). 
- UEFI es un firmware que inicializa el hardware y es capaz de entender una partición FAT y buscar un ejecutable `.EFI` con formato `PE/COFF`.

Por lo tanto, en UEFI el flujo es:
1. UEFI Firmware busca el ejecutable `.EFI`.
2. En `EFI/BOOT/BOOTX64.EFI` se ejecuta el programa.
3. El bootloader UEFI en ejecución utiliza servicios UEFI (del `EFI_SYSTEM_TABLE`) para cargar el Kernel en RAM.

## Etapa de emulación

Primeramente se realizará en QEMU para asegurarse que todo funcione.
