ASM = nasm

SRC_DIR = src
BUILD_DIR = build

all: $(BUILD_DIR)/main.img

#
# Floppy Image
#
floppy_image: $(BUILD_DIR)/main.img
$(BUILD_DIR)/main.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main.img bs=512 count=2880
	mkfs.fat -F 12 -n "JAFIOS" $(BUILD_DIR)/main.img
	dd if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main.img conv=notrunc
	mcopy -i $(BUILD_DIR)/main.img $(BUILD_DIR)/kernel.bin "::kernel.bin"

# dd copia data de un input file (if) a un output file (of)
# bs es block size, seran bloques de 512 bytes, count. /dev/zero devuelve un file de ceros
# count repite los bloques, o sea, 2880 bloques de 512 bytes = 1.33MB.
# Asi, tenemos un file de 1.33MB inicializado en cero.

#mkfs.fat = make file system with fat format, tipo (-F) 12, -n es para el label name.
# dd copia el bin de bootloader a el main img, con convencion (conv) de no truncar (file es mas pequena que el espacio total)
# mcopy, copia mas data al disco despues de haberlo movido. Se copia en el main img el contenido del kernel.bin con el label "::kernel.bin"

#
# Bootloader
#
bootloader: $(BUILD_DIR)/bootloader.bin
$(BUILD_DIR)/bootloader.bin:
	$(ASM) $(SRC_DIR)/bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin

#
# Kernel
#
kernel: $(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin:
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin