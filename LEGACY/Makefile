
# Este Makefile compila el bootloader y el kernel, crea una imagen floppy
# bootable y permite ejecutar el sistema en QEMU.

# Herramientas y rutas del proyecto.
ASM = nasm
SRC_DIR = src
BUILD_DIR = build

# Crea el directorio de salida antes de generar archivos compilados.
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Crea una imagen FAT12 con el bootloader y el kernel incluidos.
floppy_image: $(BUILD_DIR)/main.img
$(BUILD_DIR)/main.img: bootloader kernel | $(BUILD_DIR)
	dd if=/dev/zero of=$(BUILD_DIR)/main.img bs=512 count=2880
	mkfs.fat -F 12 -n "MELIOS" $(BUILD_DIR)/main.img
	dd if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main.img conv=notrunc
	mcopy -i $(BUILD_DIR)/main.img $(BUILD_DIR)/kernel.bin "::kernel.bin"

# -----------------------------------------------------------------------------
# Bootloader
# -----------------------------------------------------------------------------
# Compila el cargador de arranque desde el archivo ASM del bootloader.
bootloader: $(BUILD_DIR)/bootloader.bin
$(BUILD_DIR)/bootloader.bin: | $(BUILD_DIR)
	$(ASM) $(SRC_DIR)/bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin

# -----------------------------------------------------------------------------
# Kernel
# -----------------------------------------------------------------------------
# Compila el kernel principal en formato binario.
kernel: $(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin: | $(BUILD_DIR)
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin

# -----------------------------------------------------------------------------
# Ejecución en QEMU
# -----------------------------------------------------------------------------
# Genera la imagen y lanza qemu usando la imagen floppy como disco de arranque.
run: floppy_image
	qemu-system-x86_64 -fda $(BUILD_DIR)/main.img -rtc base=localtime

# -----------------------------------------------------------------------------
# Limpieza
# -----------------------------------------------------------------------------
# Elimina los binarios y la imagen generada por la compilación.
clear:
	rm -f $(BUILD_DIR)/*.bin
	rm -f $(BUILD_DIR)/*.img
