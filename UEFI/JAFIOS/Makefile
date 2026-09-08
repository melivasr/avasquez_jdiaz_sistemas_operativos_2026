ASM = nasm
CC = gcc
LD = ld

SRC_DIR = src
BUILD_DIR = build

# variables de boot
BOOT_SRC = $(SRC_DIR)/bootloader/boot.asm
BOOT_OBJ = $(BUILD_DIR)/boot.o
BOOT_EFI = $(BUILD_DIR)/EFI/BOOT/BOOTX64.EFI

# variables del kernel
KERNEL_SRC = $(SRC_DIR)/kernel/main.asm
KERNEL_OBJ = $(BUILD_DIR)/main.o
KERNEL_BIN = $(BUILD_DIR)/main.bin
KERNEL_ELF = $(BUILD_DIR)/main.elf

# archivo para guardar variables/estado de UEFI de la MV
OVMF_VARS = $(BUILD_DIR)/OVMF_VARS.fd

DISK = $(BUILD_DIR)/disk.img

all: $(DISK) $(OVMF_VARS) $(KERNEL_BIN)

#
# Crear directorios
#
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(OVMF_VARS): | $(BUILD_DIR) # QEMU necesita que exista el archivo en build
	cp /usr/share/OVMF/OVMF_VARS_4M.fd $@

$(BUILD_DIR)/EFI/BOOT:
	mkdir -p $(BUILD_DIR)/EFI/BOOT

#
# Ensamblar bootloader y kernel
#
$(BOOT_OBJ): $(BOOT_SRC) | $(BUILD_DIR)
	$(ASM) -f elf64 $< -o $@

$(KERNEL_OBJ): $(KERNEL_SRC) | $(BUILD_DIR)
	$(ASM) -f elf64 $< -o $@

$(KERNEL_ELF): $(KERNEL_OBJ)
	$(LD) -nostdlib \
		  -no-pie \
	      -e kernel_main \
	      -o $@ \
	      $<

$(KERNEL_BIN): $(KERNEL_ELF)
	objcopy -O binary $< $@

#
# Linkear EFI
#
$(BOOT_EFI): $(BOOT_OBJ) | $(BUILD_DIR)/EFI/BOOT
	$(LD) -nostdlib \
	      -m i386pep \
	      --subsystem 10 \
	      -e efi_main \
	      -o $@ \
	      $<

#
# Crear imagen de disco FAT
#
$(DISK): $(BOOT_EFI) $(KERNEL_BIN)
	dd if=/dev/zero of=$(DISK) bs=1M count=64
	mkfs.fat -F 32 $(DISK)
	mmd -i $(DISK) ::/EFI
	mmd -i $(DISK) ::/EFI/BOOT
	mcopy -i $(DISK) $(BOOT_EFI) ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i $(DISK) $(KERNEL_BIN) ::/main.bin

#
# Ejecutar QEMU
#
run: $(DISK) $(OVMF_VARS)
	qemu-system-x86_64 \
		-rtc base=localtime \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
		-drive if=pflash,format=raw,file=$(OVMF_VARS) \
		-drive format=raw,file=$(DISK)
#
# Limpiar
#
clean:
	rm -rf $(BUILD_DIR)