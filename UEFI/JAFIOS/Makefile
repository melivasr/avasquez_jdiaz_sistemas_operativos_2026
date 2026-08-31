ASM = nasm
CC = gcc
LD = ld

SRC_DIR = src
BUILD_DIR = build

BOOT_SRC = $(SRC_DIR)/bootloader/boot.asm
BOOT_OBJ = $(BUILD_DIR)/boot.o
BOOT_EFI = $(BUILD_DIR)/EFI/BOOT/BOOTX64.EFI

DISK = $(BUILD_DIR)/disk.img

all: $(DISK)

#
# Crear directorios
#
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/EFI/BOOT:
	mkdir -p $(BUILD_DIR)/EFI/BOOT

#
# Ensamblar bootloader
#
$(BOOT_OBJ): $(BOOT_SRC) | $(BUILD_DIR)
	$(ASM) -f elf64 $< -o $@

#
# Linkear EFI
#
$(BOOT_EFI): $(BOOT_OBJ) | $(BUILD_DIR)/EFI/BOOT
	ld -nostdlib \
	   -znocombreloc \
	   -Ttext 0x0 \
	   --subsystem 10 \
	   -e efi_main \
	   -o $@ \
	   $<

#
# Crear imagen FAT
#
$(DISK): $(BOOT_EFI)
	dd if=/dev/zero of=$(DISK) bs=1M count=64
	mkfs.fat -F 32 $(DISK)
	mmd -i $(DISK) ::/EFI
	mmd -i $(DISK) ::/EFI/BOOT
	mcopy -i $(DISK) $(BOOT_EFI) ::/EFI/BOOT/BOOTX64.EFI

#
# Ejecutar QEMU
#
run: $(DISK)
	qemu-system-x86_64 \
		-drive format=raw,file=$(DISK) \
		-bios /opt/homebrew/share/edk2/x64/OVMF_CODE.fd

#
# Limpiar
#
clean:
	rm -rf $(BUILD_DIR)