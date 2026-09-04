; ASM x86 for a basic kernel

; Recibe punteros a:
; Runtime Services -> RCX
; ConOut Services -> RDX
bits 64 ; ambiente de 64 bits para UEFI
global kernel_main 

; ============================================================
; MACRO: convierte un string ASCII a CHAR16 (UTF-16) para UEFI
; ============================================================
%macro utf16str 1
    %strlen %%len %1
    %assign %%i 1
    %rep %%len
        %substr %%c %1 %%i
        dw %%c
        %assign %%i %%i+1
    %endrep
%endmacro

; ============================================================
; CONSTANTES UEFI
; ============================================================

EFI_OUTPUTSTRING_off equ 0x8 ; offset del protocolo de OutputString desde ConOut
EFI_CLEAR_off equ 0x30 ; offset del protocolo de clear screen desde ConOut
EFI_READ_KEY_PROTOCOL_off equ 0x8 ; offset del protocolo desde ConIn
EFI_GET_TIME_off equ 0x18 ; offset del protocolo desde Runtime

; REVISAR ESTOS OFFSETS ->
EFI_CREATE_EVENT_off equ 0x50; offset desde BootServices
EFI_SET_TIMER_off equ 0x58; offset desde BootServices
EFI_WAIT_FOR_EVENT_off equ 0x60; offset desde BootServices

; ============================================================
; START
; ============================================================

kernel_main:
    mov [rel runtime_addr], rcx
    mov [rel conout_addr], rdx
    mov [rel conin_addr], r8
    mov [rel bootServices_addr], r9

    ; Preparar EFI_EVENTS Key
    lea rax, [rel efi_events] ; indice 0
    mov r8, [r8 + 0x10] ; WaitForKey en R8
    mov [rax], r8 ; guardar WaitForKey en efi_events[0]
    
    ; Boot
    lea rcx, [rel msg]
    call print

;
menu:
    ; Welcome
    call clear
    lea rcx, [rel wel_msg]
    call print
    ; Menu MSG
    lea rcx, [rel menu_msg]
    call print
;
menu_loop:
    call read_key ; devuelve ascii en ax

    cmp ax, 'r' 
    je modo_reloj

    cmp ax, 'c'
    je modo_cron

    cmp ax, 'v'
    je modo_cron

    jmp menu_loop
;
halt_loop:
    hlt
    jmp halt_loop

;
; ========================================================
; Modo_Reloj
; ========================================================

modo_reloj:
    call clear
    lea rcx, [rel reloj_msg]
    call print
    mov byte [guardar_seg], 1 ; habilitar guardar seg
    call get_time ; devuelve 
    lea rcx, [rel reloj_array]
    call print
    mov byte [guardar_seg], 0 ; deshabilitar guardar seg

modo_reloj_loop:
    ; Volver al menú
    call read_key ; devuelve ascii en ax
    cmp ax, 'v' 
    je menu

    ; Revisar el tiempo y comparar si cambia
    call get_time
    cmp ah, [seg_actual]
    jne modo_reloj

    jmp modo_reloj_loop

;
; ========================================================
; Modo_Cronometro
; ========================================================

modo_cron:
    call clear
    lea rcx, [rel cron_msg]
    call print

    ; WAIT FOR EVENT -> Esperar Evento Key
    mov rax, [rel bootServices_addr]
    mov rax, [rax + EFI_WAIT_FOR_EVENT_off] ; call
    mov rcx, 1 ; solo espera Key
    lea rdx, [rel efi_events]
    lea r8, [rel efi_events_index]

    ; shadow space 
    sub rsp, 32
    call rax ; Wait for event retornara cuando ocurra un evento
    add rsp, 32

    call read_key

    cmp ax, 's'
    je start_cron

    jmp modo_cron
;
start_cron:
    call clear 
    lea rcx, [rel cron_msg]
    call print

    mov qword [elapsed_seconds], 0 ; limpiarlo
    call create_timer ; continua a set_timer

    ; Preparar EFI_EVENTS
    lea rax, [rel efi_events] ; indice 0
    add rax, 0x08 ; moverse al indice 1
    mov r8, [rel TimerEvent]
    mov [rax], r8 ; guardar WaitForKey en efi_events[1]

    lea rcx, [rel cron_array]
    call print
;
modo_cron_loop:
    call clear 
    lea rcx, [rel cron_msg]
    call print
    ; WAIT FOR EVENT -> Esperar Evento Key o Timer
    mov rax, [rel bootServices_addr]
    mov rax, [rax + EFI_WAIT_FOR_EVENT_off]
    mov rcx, 2
    lea rdx, [rel efi_events]
    lea r8, [rel efi_events_index]

    sub rsp, 32
    call rax
    add rsp, 32

    cmp qword [efi_events_index], 0 ; ver si es Key
    je keyboard_ocurred ; si no es igual, es timer

    inc qword [elapsed_seconds] ; llevar cuenta de segundos
    ; pasar segundos a horas y tiempo
    mov rax, [elapsed_seconds] ; dividendo
    xor rdx, rdx ; limpiar parte alta: RDX:RAX
    mov rcx, 3600
    div rcx ; cociente en RAX, residuo en RDX
    ; dividir HH(seg)/3600 devuelve horas en cociente y segundos en residuo
    call binary_to_ascii
    mov [rel cron_array], al
    mov [rel cron_array+2], ah

    ; pasar segundos a horas y tiempo
    mov rax, rdx ; pasar residuo a rax
    xor rdx, rdx ; limpiar antes de dividir
    mov rcx, 60
    div rcx ; Cociente en RAX, residuo en RDX
    ; guardar minutos
    call binary_to_ascii
    mov [rel cron_array+6], al
    mov [rel cron_array+8], ah

    mov rax, rdx
    call binary_to_ascii
    mov [rel cron_array+12], al
    mov [rel cron_array+14], ah

    lea rcx, [rel cron_array]
    call print

keyboard_ocurred:
    call read_key ; devuelve ascii en ax
    cmp ax, 'v' 
    je menu
    cmp ax, 'p'
    je pausa
    jmp modo_cron_loop

pausa:
    call read_key
    cmp ax, 'v' 
    je menu
    cmp ax, 'c' ; continuar
    je modo_cron_loop

;
; ========================================================
; ReadKeyStroke. Utiliza la funcion 0x08 de ConIn Services
; Callee:
; RAX = Funct (offset 0x08)
; IN = This (RCX), puntero a key (RDX)
; Key + 2 = ascii leido
; Devuelve ascii en ax
; ========================================================

read_key:
    mov rcx, [rel conin_addr] ; this
    mov rax, [rcx + EFI_READ_KEY_PROTOCOL_off]

    lea rdx, [rel key_pointer]

    call rax

    mov ax, [rel key_pointer + 2] ; devolver ASCII es ax
    ret

;
; ========================================================
; Get time. Utiliza la funcion 0x00 de Runtime Services
; Callee:
; RAX = Funct Get Time (offset 0x00)
; IN = puntero a time (RCX), puntero a capabilities (RDX)
; Como funcion propia, guarda la cadena de chars lista 
; para imprimir en reloj_array
; ========================================================

get_time:
    mov rax, [rel runtime_addr]
    mov rax, [rax + EFI_GET_TIME_off]
    lea rcx, [rel time_pointer]
    xor edx, edx
    sub rsp, 32
    call rax
    add rsp, 32

    ; comprobar
    test rax, rax
    jz .time_ok
    lea rcx, [rel err_msg]
    call print
    ret
    
.time_ok:
    ; time_pointer: Y1,Y2, M, D, H, Min, Seg

    movzx ax, byte [rel time_pointer+4]  ; Hour
    call binary_to_ascii
    mov [rel reloj_array], al
    mov [rel reloj_array+2], ah

    movzx ax, byte [rel time_pointer+5]  ; Min
    call binary_to_ascii
    mov [rel reloj_array+6], al
    mov [rel reloj_array+8], ah

    movzx ax, byte [rel time_pointer+6]  ; Seg
    call binary_to_ascii
    mov [rel reloj_array+12], al
    mov [rel reloj_array+14], ah

    ; revisar bit para ver si guardar seg
    cmp byte [guardar_seg], 1 
    jne no_guardar
    mov [seg_actual], ah
no_guardar:
    ret

;
; ========================================================
; Binary to ASCII
; Numero a dividir: AX.
; Divide el número entre 10
; AL = decenas queda en cociente, AH = unidades en residuo
; se suma '0' para ascii
; ========================================================

binary_to_ascii:
    ; Divisor de 8 bits en BL
    ; coeficiente en AL, residuo en AH
    mov bl, 10
    div bl
    add al, '0'
    add ah, '0'
    ret
;
; ========================================================
; NOT USED 
; byte_to_char16
; Convierte un byte ASCII a CHAR16 (UTF-16) y lo escribe en memoria
; IN:  AL  = byte ASCII a convertir (ej. '0'-'9')
;      RDX = dirección destino donde escribir el CHAR16
; OUT: [RDX] queda con el word CHAR16 correspondiente
; Nota: no avanza RDX, eso lo maneja el caller
; ========================================================
byte_to_char16:
    mov ah, 0        ; limpiar el byte alto -> AX = 0x00XX (CHAR16 válido)
    mov [rdx], ax    ; escribir como word en destino
    ret

;
; ========================================================
; Print, utiliza de text output protocol su funcion 0x8
; RAX = OUTPUTSTRING
; CALLER: msg in RCX
; inside -> callee:
; RCX: IN = This = ConOut 
; RDX: direccion de Msg
; Protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x40 (64 bytes).
; ========================================================
print:
    mov rdx, rcx ; segundo argumento (msg) pasado por el caller en RCX
    mov rcx, [rel conout_addr]; This
    mov rax, [rcx + EFI_OUTPUTSTRING_off] ; call

    ; Shadow space
    sub rsp, 32
    ; ConOut->OutputString(ConOut, msg)
    call rax
    ; Restaurar stack
    add rsp, 32

    ret

;
; ========================================================
; Clear, utiliza de text output protocol su funcion 0x30
; internamente callee:
; RAX = CLEAR
; RCX: IN = This = ConOut 
; ========================================================
clear:
    mov rcx, [rel conout_addr]; This
    mov rax, [rcx + EFI_CLEAR_off] ; call

    ; Shadow space
    sub rsp, 32
    ; ConOut->ClearScreen(ConOut)
    call rax
    ; Restaurar stack
    add rsp, 32

    ret

;
; ========================================================
;CREAR TIMER EVENT
; ========================================================

create_timer:
    ; CreateEvent para Timer
    mov rax, [rel bootServices_addr]
    mov rax, [rax + EFI_CREATE_EVENT_off]  
    ; Reservar Shadow space
    sub rsp, 40h ; reservar 64 bytes en stack por comodidad
    mov rcx, 0x80000000 ; EVT_TIMER
    mov edx, 0x04 ; Nivel de prioridad de una app normal
    xor r8d, r8d ; Sin callback
    xor r9d, r9d ; Sin callback

    lea r10, [rel TimerEvent] ; puntero al evento
    mov [rsp + 32], r10 ; 5to argumento se carga en stack
    call rax
    add rsp, 64 ; restaurar stack

;
; ========================================================
; CONFIGURAR TIMER -> Set Timer
; ========================================================

set_timer_event:
    mov rax, [rel bootServices_addr]
    mov rax, [rax + EFI_SET_TIMER_off] ; call
    mov rcx, [rel TimerEvent] ; Evento Timer
    mov edx, 1 ; Tipo = TimerPeriodic
    mov r8, 10000000 ; 1 segundo 

    call rax
    ret
;
; ============================================================
; VARIABLES
; ============================================================

msg:
    utf16str "Booting from UEFI..."
    dw 13, 10, 0

wel_msg:
    utf16str "Welcome to Jafi OS!"
    dw 13, 10, 0

menu_msg:
    utf16str "Opciones: R = Reloj, C = Cronometro, A = Alarma, E = Exit to boot, V = Volver al menu"
    dw 13, 10, 0

reloj_msg:
    utf16str "Bienvenido al Modo Reloj! Opciones: V = Volver al menu"
    dw 13, 10, 0

cron_msg:
    utf16str "Bienvenido al Modo Cronometro! Opciones: V = Volver al menu"
    dw 13, 10, 0

err_msg:
    utf16str "GetTime FALLO"
    dw 13, 10, 0

; recibidos desde el bootloader
runtime_addr: dq 0;
bootServices_addr: dq 0;
conout_addr: dq 0;
conin_addr: dq 0;

; De modo reloj
time_pointer: times 2 dq 0
seg_actual: db 0
reloj_array:
    ;   0,  2,  4,  6,  8, 10, 12, 14
    dw '0','0',':','0','0',':','0','0'
    dw 13, 10, 0
guardar_seg: dw 0

; De modo cronometro

cron_array:
    ;   0,  2,  4,  6,  8, 10, 12, 14
    dw '0','0',':','0','0',':','0','0'
    dw 13, 10, 0

elapsed_seconds: dq 0
TimerEvent: dq 0

efi_events: times 2 dq 0
efi_events_index: dq 0 

; De read key
key_pointer: dq 0


