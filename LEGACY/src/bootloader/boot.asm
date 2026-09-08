ORG 0x7C00
BITS 16


; El BIOS lo carga en memoria en 0x7C00 y este codigo asume un formato
; compatible con FAT12, 512 bytes por sector.
JMP SHORT main ;Salta al inicio del programa principal
NOP

bdb_oem: DB 'MSWIN4.1' ;Identificador del sistema OEM
bdb_bytes_per_sector: DW 512 ;Cantidad de bytes por sector
bdb_sectors_per_cluster: DB 1 ;Cantidad de sectores por clúster
bdb_reserved_sectors: DW 1 ;Sectores reservados antes de la FAT
bdb_fat_count: DB 2 ;Cantidad de tablas FAT
bdb_dir_entries_count: DW 0E0h ;Cantidad máxima de entradas del directorio raíz
bdb_total_sectors: DW 2880 ;Cuantos sectores tiene el disco
bdb_media_descriptor_type: DB 0F0h ;Tipo de medio de almacenamiento
bdb_sectors_per_fat: DW 9 ;Sectores usados por cada tabla FAT
bdb_sectors_per_track: DW 18 ;Cantidad de sectors_per_track del disco
bdb_heads: DW 2 ;Cantidad de heads del disco
bdb_hidden_sectors: DD 0 ;Sectores ocultos antes de la partición
bdb_large_sector_count: DD 0 ;Total de sectores si no cabe en el campo de 16 bits

ebr_drive_number: DB 0 ;Unidad de arranque indicada por el BIOS
                DB 0 ;Campo reservado
ebr_signature: DB 29h ;Indica que existe una EBR extendida
ebr_volume_id: DB 12h, 34h, 56h, 78h ;Identificador único del volumen
ebr_volume_label: DB 'MELI OS    ' ;Nombre del volumen
ebr_system_id: DB 'FAT12   ' ;Tipo de sistema de archivos


; Inicializa el entorno y carga el kernel desde el disco.
main:
    MOV AX, 0
    MOV DS, AX
    MOV ES, AX
    MOV SS, AX

    MOV SP, 0x7C00 ;Inicializa la pila 

    MOV [ebr_drive_number], DL ;Guarda la unidad de arranque indicada por el BIOS
    MOV AX, 1
    MOV CL, 1
    MOV BX, 0x7E00
    call disk_read ;Lee el primer sector del volumen para preparar la estructura FAT

    MOV SI, os_boot_msg
    CALL print ;Muestra el mensaje de inicio

    ;4 segments
    ;reserved segment: 1 sector
    ;FAT: 9*2 = 18 sectors
    ;Estos dependen de la compu
    ;root directory: 
    ;data: 
    
    MOV AX, [bdb_sectors_per_fat]
    MOV BL, [bdb_fat_count]
    XOR BH, BH
    MUL BX
    ADD AX, [bdb_reserved_sectors];LBA of the root directory
    PUSH AX

    MOV AX, [bdb_dir_entries_count] ;Número total de entradas del directorio raíz
    SHL AX, 5 ;AX *=32 porque cada entrada ocupa 32 bytes
    XOR DX, DX ;Limpia residuo para la división
    DIV word [bdb_bytes_per_sector] ;Calcula cuántos sectores ocupa el directorio raíz

    TEST DX, DX ;Comprueba si hay residuo en la división
    JZ rootDirAfter ;Si no hay residuo, se usa el cociente exacto
    INC AX ;Redondea hacia arriba si el directorio ocupa parte de otro sector

rootDirAfter:
    MOV CL, AL
    POP AX
    MOV DL, [ebr_drive_number]
    MOV BX, buffer
    CALL disk_read ;Carga el directorio raíz en el buffer

    XOR BX, BX
    MOV DI, buffer

; Busca KERNEL.BIN dentro del directorio raiz. Cada entrada ocupa 32 bytes
; y el nombre del archivo debe coincidir exactamente con 11 bytes.
searchKernel:
    MOV si, file_kernel_bin
    MOV CX, 11
    PUSH DI
    REPE CMPSB ;Compara 11 bytes del nombre del archivo con la entrada actual
    POP DI
    JE foundKernel ;Salta si encontró la entrada de KERNEL.BIN

    ADD DI, 32 ;Cada entrada del directorio ocupa 32 bytes
    INC BX ;Siguiente entrada del directorio
    CMP BX, [bdb_dir_entries_count]
    JL searchKernel ;Continua buscando si no se recorrieron todas

    JMP kernelNotFound
; Muestra un error cuando no se encuentra el kernel.
kernelNotFound:
    MOV SI, kernel_not_found_msg ;Mensaje de error cuando no existe KERNEL.BIN
    CALL print ;Muestra el error en pantalla
    HLT ;Detiene la CPU para evitar seguir ejecutando sin kernel
    JMP halt  ;Entra en un bucle inactivo

; Obtiene el clúster inicial y prepara la carga del kernel.
; En FAT12 cada entrada del directorio guarda en la posicion 26 el primer
; clúster del archivo; luego se sigue la cadena de clusters en la FAT.
foundKernel:
    MOV AX, [DI+26]
    MOV [kernel_cluster], AX

    MOV AX, [bdb_reserved_sectors]
    MOV BX, buffer
    MOV CL, [bdb_sectors_per_fat]
    MOV DL, [ebr_drive_number]

    CALL disk_read ;Carga la FAT en memoria para seguir la cadena del archivo

    MOV BX, kernel_load_segment
    MOV ES, BX
    MOV BX, kernel_load_offset

; Carga cada clúster del kernel y consulta la FAT por el siguiente.
; La formula (cluster * 3) / 2 es la forma usual de obtener los 12 bits
; de la FAT12 asociados al cluster actual.
loadKernelLoop:
    MOV AX, [kernel_cluster] ;Recupera el cluster actual del kernel
    ADD AX, 31 ;Convierte el cluster a LBA del dato real en disco
    MOV CL, 1 ;Lee solo un sector por iteración
    MOV DL, [ebr_drive_number] ;Especifica la unidad de disco
    CALL disk_read ;Lee el clúster actual del kernel
    ADD BX, [bdb_bytes_per_sector] ;Avanza la dirección de destino en memoria

    MOV AX, [kernel_cluster] ;(kernel cluster*3)/2
    MOV CX, 3
    MUL CX
    MOV CX, 2
    DIV CX

    MOV SI, buffer
    ADD SI, AX
    MOV AX, [DS:SI]

    OR DX, DX
    JZ even
odd: 
    SHR AX, 4
    JMP nextClusterAfter
even:
    AND AX, 0x0FFF
nextClusterAfter:
    CMP AX, 0X0FF8
    JAE readFinish ;Termina al encontrar el marcador de fin de cluster

    MOV [kernel_cluster], AX
    JMP loadKernelLoop
; Transfiere la ejecución al kernel cargado en memoria.
readFinish:     
    MOV DL, [ebr_drive_number]
    MOV AX, kernel_load_segment
    MOV DS, AX
    MOV ES, AX

    JMP kernel_load_segment:kernel_load_offset ;Inicia la ejecución del kernel

    HLT   

; Mantiene la CPU detenida en un ciclo infinito.
halt:
    JMP halt

; Convierte una direccion LBA a los valores CHS requeridos por el BIOS.
; En un disco geometrico, cada LBA debe convertirse a cylinder, head y sector.
; La formula basica es: sector = (LBA % sectors_per_track) + 1,
; head = (LBA / sectors_per_track) % heads,
; cylinder = (LBA / sectors_per_track) / heads.
;input: LBA index in ax
;cx [bits 0-5 ] sector number (1-63)
;cx [bits 6-15] cylinder number (0-1023)
;dh: head number (0-255)
lba_to_chs: 
    PUSH AX
    PUSH DX

    XOR DX, DX
    DIV word [bdb_sectors_per_track] ;LBA / sectors_per_track; el residuo queda en DX
    INC DX ;Sector = (LBA % sectors_per_track) + 1
    MOV CX, DX

    XOR DX, DX
    DIV word [bdb_heads] ;Se obtiene head y cylinder a partir del cociente anterior
    
    MOV DH, DL ;DH = head

    MOV CH, AL ;CH = bits bajos del cylinder
    SHL AH, 6
    OR CL, AH ;AH aporta los bits altos del cylinder dentro del campo de sector

    POP AX
    MOV DL,AL
    POP AX
    RET

; Lee sectores del disco mediante la interrupción 13h del BIOS.
disk_read:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH DI

    call lba_to_chs ;Convierte la dirección LBA a CHS

    MOV AH, 02h
    MOV DI, 3 ;counter

retry: 
    STC
    INT 13h ;Solicita la lectura de sectores al BIOS
    JNC doneRead ;Continúa si la lectura fue exitosa

    CALL diskReset

    DEC DI
    TEST DI, DI
    JNZ retry

failDiskRead:
    MOV SI, read_failure ;Mensaje de fallo al leer el disco
    CALL print ;Muestra el error por pantalla
    HLT ;Se queda detenido porque la carga del sistema falló
    JMP halt

; Restablece el controlador de disco para reintentar una lectura.
diskReset:
    PUSHA
    MOV AH, 0
    STC
    INT 13h ;Restablece el disco usando el BIOS
    JC failDiskRead
    POPA
    RET

; Restaura los registros y vuelve de la lectura de disco.
doneRead:
    POP DI
    POP DX
    POP CX
    POP BX
    POP AX
    RET

; Muestra una cadena terminada en cero usando los servicios de video del BIOS.
print: 
    PUSH SI
    PUSH AX
    PUSH BX

print_loop:
    LODSB ;Carga el siguiente carácter del string
    OR AL, AL ;Comprueba si llegó al terminador 0
    JZ print_done ;Termina al encontrar el fin de la cadena
    MOV AH, 0x0E ;Selecciona la función de impresión del BIOS
    MOV BH, 0x00 ;Página de video 0
    INT 0x10 ;Imprime el carácter en la consola
    JMP print_loop ;Sigue con el siguiente carácter

print_done: 
    POP BX
    POP AX
    POP SI
    RET

os_boot_msg:
    DB "Booting meliOS...", 0x0D, 0x0A,0
read_failure:
    DB "Disk read failure", 0x0D, 0x0A,0    

file_kernel_bin: DB 'KERNEL  BIN'
kernel_not_found_msg: DB 'KERNEL.BIN not found!', 0x0D, 0x0A, 0
kernel_cluster: DW 0
kernel_load_segment: EQU 0x2000
kernel_load_offset: EQU 0

TIMES 510-($-$$) DB 0
DW 0AA55h

buffer: 
