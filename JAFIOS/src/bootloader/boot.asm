;ASM x86 for a basic bootloader

org 0x7C00 ;Directiva NASM. Indica direccion de origen del codigo.
bits 16 ;Directiva NASM. Indica modo de ensamblado.
;Se inicia en 16 bits para retro-compatibilidad

; ==================================================================
; HEADER del disco para cumplir con la info de formato FAT 12
; BASADO EN LA DOCUMENTACION DE LOS DISCOS
; ==================================================================
jmp short main ; salto proximo para saltar el header.
nop ; para evitar riesgo ???

bdb_oem:                    db  'MSWIN4.1' ; estandar
bdb_bytes_per_sector:       dw  512 ;512 bytes por sector
bdb_sectors_per_cluster:    db  1; 1 sector por cluster
bdb_reserved_sectors:       dw  1; 1 sector reservado
bdb_fat_count:              db  2; cuantos fat hay en el disco
bdb_dir_entries_count:      dw  0E0h; numero estandar de entradas de directorio en el disco
bdb_total_sectors:          dw  2880; 2880 sectores de 512 bytes. Mismo que el makefile
bdb_media_descriptor_type:  db 0f0h; estandar
bdb_sectors_per_fat:        dw  9; estandar
bdb_sectors_per_track:      dw  18; estandar
bdb_heads:                  dw 2; estandar

bdb_hidden_sectors:         dd 0; estandar
bdb_large_sector_count:     dd 0; estandar

ebr_drive_number:           db 0; estandar
                            db 0; cero quemado, estandar
ebr_signature:              db 29h; estandar
ebr_volume_id:              db 12h, 34h, 56h, 78h ; estandar
ebr_volume_label:           db 'JAFI OS    ' ;debe de ser de size=11 bytes, o sea, exactamente 11 chars
;JAFI OS     = 6 letras/chars + 1 espacio en medio + 4 espacios despues
ebr_system_id:              db 'FAT12   ';debe ser de size=8bytes, 5letras +3 espacios

; ==================================================================
; BOOTLOADER PROGRAM
; ==================================================================

main:

; set up consistente del programa
basic_setup:
    mov ax, 0 ;cargar 0 en registro general de 16 bits
    mov ds, ax ;cargar 0 en el data segment
    mov es, ax ;0 en el extra segment
    mov ss, ax ;0 en el stack segment

    mov sp, 0x7C00 ;iniciar el stack despues de nuestra aplicacion

main_read:
    mov [ebr_drive_number], dl ; en dl debe ir el drive number segun la docu
    mov ax, 1 ; LBA index a leer. Debe pasarse a CHS
    mov cl, 1 ; por docu
    mov bx, 0x7E00 ; puntero a buffer que existe en el disco
    call disc_read

    ; Set Up para leer del disco
    mov si, os_boot_msg ; guardar en source index el msg
    call print

    ; 4 segmentos
    ; reserved segment = 1 sector
    ; FAT segment = 9*2 = 18 sectors
    ; Root Directory Segment = 1 sector (in the 19th sector)
    ; Data segment 

    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh ; limpiar bh
    mul bx ; MUL multiplica siempre con ax, Devuelve FAT segment
    add ax, [bdb_reserved_sectors] ; estamos sumando 9*2 (que esta en ax) + 1, lo cual devuelve 19, el LBA del root directory

    push ax

    mov ax, [bdb_dir_entries_count]
    shl ax, 5 ; ax * 32 (pues 2^5 = 32)
    xor dx, dx ; limpiar residuo
    div word [bdb_bytes_per_sector] ; (32* num_of_entries)/bytes_per_sectors = total number of sectors a leer
    
    test dx, dx ; verificar si hubo residuo
    jz rootDirAfter ; si no hay, se salta
    inc ax ; si hubo residuo, sumamos 1 para hacer redondeo

rootDirAfter:
    mov cl, al ; mover a cl el al que contiene el total number of sectors a leer
    pop ax ; devolver el LBA del root directory que habiamos hecho push
    mov dl, [ebr_drive_number] ; para saber de cual Drive leer.
    mov bx, buffer ; mover el buffr a bx
    call disk_read ; leer el disco

    xor bx, bx ; limpia bx, bx = 0
    mov di, buffer ; queda cargado el root directory en memoria y en di su direccion !

; Ahora hay que buscar el Kernel
search_kernel:
    mov si, file_kernel_bin ; mover el nombre del kernel file a SourceIndex
    mov cx, 11 ; poner el tamaño (bytes) del nombre a cx

    push di ; preservar DI

    REPE CMPSB ; REPE repite instrucciones. CMPSB compara bytes CX veces ( o sea, compara 11 bytes) entre el SI y el DI. 
    ; Note que en SI esta el nombre del Kernel y en DI esta el buffer al root directory en mem

    pop di ; recuperar di porque ya terminamos de operar

    je foundKernel ; si cmpsb encuentra que el nombre es igual al buffer, devuelve un equal

    ; Que pasa si no lo encontró? Tenemos que seguir buscando
    add di, 32 ; aumentar el buffer en 32 
    inc bx ; bx es nuestro contador de entradas
    cmp bx, bdb_dir_entries_count ; ya leimos todas las entradas de directorio?
    jl searchKernel ; si es menor, entonces no hemos leido todas y buscamos otra vez en el kernel con el buffer offseteado
    jmp kernelNotFound ; si no es menor, entonces si leimos todas y NO se encontro el kernel

kernelNotFound:
    mov si, msg_kernel_not_found
    call print

    hlt; congela cpu hasta que ocurra una interrupcion , por si hay no esperadas.
    jmp halt

foundKernel:
    mov ax, [di+26]; encontrar el cluster asociado al kernel
    ; di es la direccion del kernel. 26 es un offset al First Logical Cluster Field
    mov [kernel_cluster], ax ; mover el cluster encontrado a la variable

    ; preparar Disk Read
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    
    call disk_read

    ; setear la memoria a la que le vamos a cargar la data del kernel
    mov bx, kernel_load_segment ; la cargamos en 0x2000
    mov es, bx ; en INT 13h, el buffer es es calling bx
    mov bx, kernel_load_offset ; con un offset de cero

loadKernelLoop:
    mov ax, [kernel_cluster] ; current cluster that we are reading
    add ax, 31 ; setea el offset para poder leer el cluster que queremos. Cambia segun disco, deberia ser dinamico pero por ahora quemado sirve
    mov cl, 1 ; numero de sectores a leer
    mov dl, [ebr_drive_number]

    ; leemos un sector del kernel cluster a la vez
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; debemos encontrar la posicion del siguiente cluster a leer, con la formula (kernel_cluster*3)/2
    mov ax, [kernel_cluster] ; poner el kernel cluster actual otra vez en ax por si disk_read lo sobreescribió
    mov cx, 3
    mul cx ; multiplicar ax*cx = kernel_cluster * 3
    mov cx, 2
    div cx ; dividir ax/cx = (kernel_cluster*3)/2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]
    
    ; FAT 12 es 12 bytes por cluster. para obtener el cluster real hay que manipular un poco.
    ; Si la div fue par (sin residuo), se toma los 12 bits mas bajos
    ; Si la div fue impar (con residuo), se toma los 12 bits mas altos

    or dx, dx
    jz even ; si es zero, entonces dx no devolvió residuo (dx = 0 para even, =1 para odd)

odd:
    shr ax, 4 ; quita 4 bits de abajo y mete 4 ceros arriba
    jmp nextCluster

even:
    and ax, 0x0FFF ; devuelve los otros 12 bits

nextClusterAfetr:
    cmp ax, 0x0FF8 ; chequear si llegamos a final de la tabla FAT ?
    jae readKernelFinish

    ; si no hemos llegado al final
    mov [kernel_cluster], ax ; poner el nuevo cluster (ax) en la variable 
    jmp loadKernelLoop

readKernelFinish:
    ; queremos saltar al kernel, seteamos valores
    mov dl, [ebr_drive_number]
    mov ax, kernel_load_segment
    mov ds, ax
    mov es, ax

    jmp kerne_load_segment:kernel_load_offset ; es un jump largo, a otro file

    hlt ; detener ejecucion por si el salto falló

; ==============================
; FUNCIONES AUXILIARES
; ==============================

; bucle si ocurren interrupciones
halt_loop:
    hlt ;
    jmp halt_loop


; ==============================
; DISK READ FUNCTIONS
; incluye proceso de intentar hacer LBA to CHA.
; Luego intenta lectura con INT 13h al menos 3 veces
; si fallá, se queda en hlt o va a halt_loop
; flujo: main_read -> disk_read -> lba_to_cha -> retry
    ; retry -> done_read si no falló
    ; retry -> calls disk_reset -> jumps to fail_disk_read si no pudo resetear
    ;                         o -> rets retry (3 times) -> transitions to fail_disk_read if more 3 times
; ==============================

; LBA TO CHS FUNCTION
; input: LBA index in ax
; cx [0:5]: sector number 
; cx [15:6]: cylinder (bits 9 y 8 en parte baja, bits 0-7 en alta)
; dh: head
lba_to_chs:
    push ax ; guarda ax
    push dx 

    ; ===================================
    ; CALCULAR t y s
    ; ===================================

    ; Poner dx en cero (igual a mov dx, 0, pero mas eficiente)
    xor dx, dx ; limpiar registro donde queda el residuo
    ; realiza t = LDA/bdb_sectors_per_track, pues LDA = ax.
    div word [bdb_sectors_per_track] ; deja residuo en dx y el cociente en ax
    ; LBA % bdb_bytes_per_sector = residuo de la división
    inc dx ; (LBA % bdb_bytes_per_sector) + 1 = sector = dx
    mov cx, dx ; guardar sector = s = dx en cx

    ; ===================================
    ; CALCULAR h y c
    ; ===================================
    ; HEAD = t % number_of_heads = LDA/bdb_sectors_per_track % number_of_heads
    ; CYLINDER = t / number_of_headers = LDA/bdb_sectors_per_track / number_of_heads
    ; Recordando que reg ax AUN contiene LDA/bdb_sectors_per_track... dividir entre number _of_heads

    xor dx, dx ; limpiar el registro de residuo
    div word [bdb_heads] ; esto deja el residuo h en dx y el cociente c en ax

    ; ===================================
    ; PREPARAR OUTPUTS 
    ; CX[15:8] = bits 7:0 del Cylinder
    ; CX[7:6]  = bits 9:8 del Cylinder
    ; CX[5:0]  = Sector
    ; dh: head
    ; ===================================

    mov dh, dl ; mover dl (el head que se guardo en la parte baja de dx) a la parte alta dh
    ; cylinder está en AL y ah pues podria ser de 16 bits max.
    mov ch, al ; mover AL (el cylinder [7:0]) que se guardó en la parte baja de ax) a la parte alta ch
    ; esto es lo mismo que CX[15:8] = bits 7:0 del Cylinder
    ; Ahora, ocupamos cylinder [9:8] en la parte baja
    shl ah, 6; por ejemplo AH = 00000001 -> 01000000. Asi, los dos bits que ocupamos [9:8} quedan en lo mas alto [15:14]
    or cl, ah ; sector ya esta en cl. OR pone los bits 9:8 (ahora en 15:14) de AH en cl. 
    ; esto funciona porque sector es maximo 2^6, por lo que jamas llegar a estar en los bits [7:6] 
    ; el OR no afecta lo que ya existía, pone 1 en los bits 6 o 7 si asi se requiere.
    ; por ejemplo, con sector = 63 (lo maximo) : 01000000 OR 00111111 = 01111111

    pop ax
    mov dl, al
    pop ax ; ax otra vez porque en dl pusimos al

    ret


; funcion para leer el disco con INT 13 convirtiendo LBA en CHS
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    call lba_to_chs

    mov ah, 02h
    mov di, 3 ; counter para repetir al menos 3 veces por si hay algun error no fatal en el disco.

retry:
    stc ; set del carry para ver si hubo error
    INT 13h ; intenta la rutina de lectura ya con los valores que dejó lba_to_cha en disk_read
    jnc done_read ; si No hay Carry, no hubo error

    ; si si hubo, hay que intentar otra vez
    call disk_reset

    dec di ; di --
    test di, di ; verificar si no se llego a cero
    jnz retry ; si test No es Zero, hace retry, solo pasa a fail_disk_read si DI pasó de 3 a 0

fail_disk_read:
    mov si, fail_read_disk_msg
    call print
    hlt ; se queda esperando porque si llegamos aqui, ya se intentó 3 veces y falló
    jmp halt_loop ; in case hlt fails

disk_reset:
    pusha ; push all general reg onto stack
    mov ah, 0
    stc ; set carry
    INT 13h
    jc fail_disk_read ; si hay carry, es un error y debe ir a fail
    ; si no falló
    popa ; pop all
    ret ; volver a retry a intentar otra vez

done_read;
    ;restaurar stack
    pop di
    pop dx
    pop cx
    pop bx
    pop ax

    ret ; se logró leer, entonces se retorna al flujo de main



; loop para prints
print:
    push si ;guardar source index en el stack
    push ax
    push bx
print_loop:
    lodsb ;cargar (load) en la parte baja de ax (al) un byte (8bits) de el source index, un char
    ;si el char SI es 0, es el fin del string y dejamos de imprimir.
    or al, al ;si en al (parte baja) hay un 0, 0 or 0 = 0
    jz done_print ;salta si flag cero se levanta

    ;si NO es un cero, entonces es un char valido (no end of line)
    mov ah, 0x0E ; indicador de impresion en screen
    mov bh, 0 ; bh es el page number, es usado para multiples monitores.
    INT 0x10 ; VIDEO INTERRUPT, busca ax y bx y hace la rutina de impresion

    jmp print_loop ;seguir imprimiendo hasta encontrar cero

done_print:
    pop bx
    pop ax
    pop si

;============================
; VARIABLES
;============================
os_boot_msg: db 'Loading...', 0x0D, 0x0A, 0; 0 es para indicar el fin del string, hexas son new line characters 
fail_read_disk_msg: db 'Failed to read disk', 0x0D, 0x0A, 0;
file_kernel_bin db 'KERNEL  BIN' ; cumplir con los 11 bytes
msg_kernel_not_found db 'KERNEL.BIN not found'
kernel_cluster dw 0 ; cual cluster está? es definido por foundKernel

kernel_load_segment equ 0x2000 ; reservar esta area de memoria para el kernel
kernel_load_offset equ 0


;============================
; Fin del programa
;============================
; llenar los 510 bytes
rellenado:
    times 510-($-$$) db 0 ; Directivas NASM. times -> Repite datos, db -> define byte
    ; $ = pos actual dentro del codigo
    ; $$ = inicio de seccion actual (linea 0 del codigo)
    ; $-$$ = bytes dentro del codigo
    ; Entonces, se escribe el byte 0 un total de 510-bytes en el codigo
    ; Asi, se consigue rellenar de ceros y llegar a los ultimos 2 bytes 

; poner 55AA al final del MBR
firma:
    dw 0xAA55 ; Directiva NASM. Define word (2 bytes)
    ; por ser little endian, se acomoda:
    ; 510: 0x55
    ; 511: 0xAA
    ; Asi, como el sector permitido por legacy (MBR) es de 512 bytes
    ; en los ultimos 2 bytes (510,511) va a encontrar el identificador 55AA

buffer: ; buffer BX para leer del disco y ponerlo ahi