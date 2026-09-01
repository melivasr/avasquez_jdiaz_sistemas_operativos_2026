; ASM x86 for a basic kernel

bits 64 ; ambiente de 64 bits para UEFI
global kernel_main 

kernel_main:
    hlt