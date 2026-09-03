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

EFI_TEXT_OUT_PROTOCOL_off equ 0x8 ; offset del servicio de OutputString desde ConOut
EFI_READ_KEY_PROTOCOL_off equ 0x8 ; offset del servicio de OutputString desde ConOut
EFI_GET_TIME_off equ 0x18 ; offset desde Runtime

; ============================================================
; START
; ============================================================

kernel_main:
    mov [rel runtime_addr], rcx
    mov [rel conout_addr], rdx
    mov [rel conin_addr], r8
    
    ; Boot
    lea rcx, [rel msg]
    call print
;
menu:
    ; Welcome
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
    mov byte [guardar_seg], 1
    call get_time ; devuelve 
    lea rcx, [rel reloj_array]
    call print
    mov byte [guardar_seg], 0

modo_reloj_loop:
    ; Volver al menú
    call read_key ; devuelve ascii en ax
    cmp ax, 'v' 
    je menu

    ; cambiar al segundo
    call get_time
    cmp ah, [seg_actual]
    jne modo_reloj

    jmp modo_reloj_loop

;
; ========================================================
; ReadKeyStroke. Utiliza la funcion 0x08 de ConIn Services
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
; NOT USED byte_to_char16
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
; RAX = TEXT OUTPUT PROTOCOL
; CALLER: msg in RCX
; inside ->
; RCX: IN = This = ConOut 
; RDX: direccion de Msg
; Protocolo de salida de texto de UEFI. En x86-64, tiene offset 0x40 (64 bytes).
; ========================================================
print:
    mov rdx, rcx ; segundo argumento (msg) pasado por el caller en RCX
    mov rcx, [rel conout_addr]; This
    mov rax, [rcx + EFI_TEXT_OUT_PROTOCOL_off] ; call

    ; Shadow space
    sub rsp, 32
    ; ConOut->OutputString(ConOut, msg)
    call rax
    ; Restaurar stack
    add rsp, 32

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

err_msg:
    utf16str "GetTime FALLO"
    dw 13, 10, 0

; recibidos desde el bootloader
runtime_addr: dq 0;
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

; De read key
key_pointer: dq 0


