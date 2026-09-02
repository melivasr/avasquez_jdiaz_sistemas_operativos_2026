#!/bin/bash 

echo " 🗑️ Limpiando la carpeta build... "
rm -rf build/*

echo " ⌛️ Preparando ambiente... "
make

echo " 🎮 Iniciando Emulación "
qemu-system-i386 -fda build/main.img -rtc base=localtime