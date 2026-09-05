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
    push rbp
    mov rbp, rsp
    and rsp, -16      ; fuerza RSP a múltiplo de 16, 
    ; sin importar cómo se haya llamado el firmware/bootloader
    mov [rel runtime_addr], rcx

    mov [rel conout_addr], rdx
    mov [rel conin_addr], r8
    mov [rel bootServices_addr], r9

    ; Preparar EFI_EVENTS Key
    lea rax, [rel efi_events] ; indice 0
    mov r8, [r8 + 0x10] ; WaitForKey en R8
    mov [rax], r8 ; guardar WaitForKey en efi_events[0]

    call create_timer ;
    
    test rax, rax
    jnz error

    cmp qword [rel TimerEvent], 0
    je error

    ; Preparar EFI_EVENTS Timer
    lea rax, [rel efi_events] ; indice 0
    add rax, 0x08 ; moverse al indice 1
    mov r8, [rel TimerEvent]
    mov [rax], r8 ; guardar TimerEvent en efi_events[1]

    call set_timer_event
    
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

    cmp ax, 'a'
    je modo_alarma

    cmp ax, 'e'
    je exit

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
    cmp ax, 'w'
    je modo_cron
    cmp ax, 'e'
    je exit

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
;
modo_cron_loop:
    call read_key

    cmp ax, 's'
    je start_cron

    cmp ax, 'c'
    je continue_cron

    cmp ax, 'v'
    je menu

    cmp ax, 'w'
    je modo_reloj

    cmp ax, 'e'
    je exit

    jmp modo_cron_loop
;
start_cron:
    mov qword [rel elapsed_seconds], 0 ; limpiarlo

continue_cron:
    call clear 
    lea rcx, [rel in_cron_msg]
    call print

    lea rcx, [rel cron_array]
    call print
;
in_cron_loop:
    call clear 

    lea rcx, [rel in_cron_msg]
    call print

    lea rcx, [rel cron_array]
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

    cmp qword [rel efi_events_index], 0
    je keyboard_ocurred

    cmp qword [rel efi_events_index], 1
    je timer_happened

    jmp in_cron_loop

    
;
timer_happened:
    mov byte [rel debug_array], 'T'
    inc qword [rel elapsed_seconds] ; llevar cuenta de segundos
    ; pasar segundos a horas y tiempo
    mov rax, [rel elapsed_seconds] ; dividendo
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

    jmp in_cron_loop
;
keyboard_ocurred:
    call read_key ; devuelve ascii en ax
    cmp ax, 'v' 
    je menu
    cmp ax, 'p'
    je pausa
    cmp ax, 'w'
    je modo_reloj
    cmp ax, 'r'
    je reiniciar
    cmp ax, 'e'
    je exit
    jmp in_cron_loop
;
pausa:
    call clear 

    lea rcx, [rel pausa_msg]
    call print

    lea rcx, [rel cron_array]
    call print
;
pausa_loop:

    call read_key
    cmp ax, 'v' 
    je menu
    cmp ax, 'w'
    je modo_reloj 
    cmp ax, 'c' ; continuar
    je in_cron_loop
    cmp ax, 'r'
    je reiniciar
    cmp ax, 'e'
    je exit

    jmp pausa_loop
;
reiniciar:
    mov byte [rel cron_array], '0'
    mov byte [rel cron_array+2], '0'
    mov byte [rel cron_array+6], '0'
    mov byte [rel cron_array+8], '0'
    mov byte [rel cron_array+12], '0'
    mov byte [rel cron_array+14], '0'
    mov qword [rel elapsed_seconds], 0
    jmp in_cron_loop

;
; ========================================================
; Modo_Cronometro
; ========================================================

modo_alarma:
    lea rcx, [rel alarma_msg]
    call prints

; ============================================================
; read_alarm. Usa Read Key
;
; Salida:
;   [alarm_hour]   = hora
;   [alarm_minute] = minuto
;
; Ejemplo:
;   14 35<ENTER>
;
; ============================================================

read_alarm:

    ; Inicializar
    mov word [current_number], 0
    mov byte [input_state], 0

.read_key:

    call read_key

    cmp ax, 13                  ; '\r'
    je .enter

    cmp ax, ' '
    je .space

    ; digito

    cmp ax, '0'
    jb .read_key

    cmp ax, '9'
    ja .read_key

    ; --------------------------------------------------------
    ; Convertir ASCII → número
    ;
    ; '0' -> 0
    ; '1' -> 1
    ; ...
    ; '9' -> 9
    ; --------------------------------------------------------

    sub ax, '0'

    ; --------------------------------------------------------
    ; current_number = current_number * 10 + digit
    ; --------------------------------------------------------

    movzx eax, ax
    movzx edx, word [current_number]

    imul edx, edx, 10
    add edx, eax

    mov [current_number], dx

    jmp .read_key


; ============================================================
; SPACE
; ============================================================

.space:

    cmp byte [input_state], 0
    jne .read_key

    ; --------------------------------------------------------
    ; Estamos terminando de introducir la hora
    ; --------------------------------------------------------

    mov ax, [current_number]

    ; Validar 0 <= HH <= 23
    cmp ax, 23
    ja .invalid

    mov [alarm_hour], al

    ; --------------------------------------------------------
    ; Cambiar a modo MINUTOS
    ; --------------------------------------------------------

    mov byte [input_state], 1
    mov word [current_number], 0

    jmp .read_key


; ============================================================
; ENTER
; ============================================================

.enter:

    ; Enter solamente es válido después de los minutos
    cmp byte [input_state], 1
    jne .read_key

    mov ax, [current_number]

    ; Validar 0 <= MM <= 59
    cmp ax, 59
    ja .invalid

    mov [alarm_minute], al

    ret


; ============================================================
; Entrada inválida
; ============================================================

.invalid:

    ; Aquí podrías imprimir:
    ;
    ; "Hora invalida"
    ;
    ; y volver a comenzar.

    mov word [current_number], 0
    mov byte [input_state], 0

    jmp .read_key

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

    sub rsp, 32
    call rax
    add rsp, 32

    mov ax, [rel key_pointer + 2] ; devolver ASCII en ax
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
; Protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x32 (64 bytes).
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
    sub rsp, 48 ; reservar 40+8 bytes en stack 
    mov rcx, 0x80000000 ; EVT_TIMER
    mov edx, 0x04 ; Nivel de prioridad de una app normal
    xor r8d, r8d ; Sin callback
    xor r9d, r9d ; Sin callback

    lea r10, [rel TimerEvent] ; puntero al evento
    mov [rsp + 32], r10 ; 5to argumento se carga en stack
    call rax
    add rsp, 48 ; restaurar stack

    ret

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

    ; shadow space
    sub rsp, 32
    call rax
    add rsp, 32
    ret
;
; ========================================================
; CANCELAR TIMER -> Usa Set Timer
; ========================================================
cancel_timer:
    mov rax, [rel bootServices_addr]
    mov rax, [rax + EFI_SET_TIMER_off]
    mov rcx, [rel TimerEvent]
    mov edx, 0          ; TimerCancel
    xor r8, r8          ; TriggerTime ignorado en cancel

    sub rsp, 32
    call rax
    add rsp, 32
    ret
;
; ========================================================
; Error no fatal
; ========================================================
error:
    mov rcx, [rel err_msg]
    call print
    jmp error

;
; ========================================================
; Volver a UEFI
; ========================================================
exit:
    mov rsp, rbp
    pop rbp
    ret
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
    utf16str "Opciones: R = Reloj, C = Cronometro, A = Alarma, E = Exit to boot"
    dw 13, 10, 0
;
reloj_msg:
    utf16str "Bienvenido al Modo Reloj! Opciones: V = Volver al menu, W = Cambiar de modo"
    dw 13, 10, 0
;
cron_msg:
    utf16str "Bienvenido al Modo Cronometro! Opciones: S = Iniciar (en 0), C = Continuar, V = Volver al menu, W = Cambiar de modo"
    dw 13, 10, 0
;
in_cron_msg:
    utf16str "Cronometro en curso!: Opciones: P = Pausar, R = Reiniciar, V = Volver al menu, W = Cambiar de modo"
    dw 13, 10, 0
;
pausa_msg:
    utf16str "Cronometro en pausa!: Opciones: C = Continuar, R = Reiniciar, V = Volver al menu, W = Cambiar de modo"
    dw 13, 10, 0
;
alarma_msg:
    utf16str "Bienvenido al Modo Alarma. Ingrese la hora"
    dw 13, 10, 0

;
err_msg:
    utf16str "GetTime FALLO"
    dw 13, 10, 0
;
; ADDR recibidos desde el bootloader
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

debug_array:
    ;   0,  2,  4,  6,  8, 10, 12, 14
    dw '2'
    dw 13, 10, 0

elapsed_seconds: dq 0
TimerEvent: dq 0

efi_events: times 2 dq 0
efi_events_index: dq 0 

; De read key
key_pointer: dq 0

; Para alarma
alarm_hour      db 0
alarm_minute    db 0

current_number  dw 0
input_state     db 0        ; 0 = hora, 1 = minutos

key:
    dw 0                    ; ScanCode
    dw 0                    ; UnicodeChar

