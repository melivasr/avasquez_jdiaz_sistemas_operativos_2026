ORG 0x0 ; Define el origen del código en la dirección 0x0000
BITS 16 ; Modo de 16 bits

main:
    MOV AX, CS ; 
    MOV DS, AX 
    MOV ES, AX    

    MOV SI, os_boot_msg 
    CALL print 

halt:
    CLI ; Deshabilita las interrupciones 
    HLT ; Detiene la CPU hasta que ocurra una interrupción
    JMP halt; Mantiene el sistema detenido de forma indefinida

print: 
    PUSH SI 
    PUSH AX            
    PUSH BX            

print_loop:
    LODSB ; Carga el siguiente carácter en AL y avanza SI
    OR AL, AL ; Comprueba si el carácter es el terminador nulo
    JZ print_done ; Finaliza si se llegó al final de la cadena
    MOV AH, 0x0E        
    MOV BH, 0x00        
    INT 0x10  ; Invoca al BIOS para imprimir el carácter en AL
    JMP print_loop ; Continúa con el siguiente carácter

print_done: 
    ;Restauramos
    POP BX         
    POP AX              
    POP SI              
    RET               

os_boot_msg:
    DB "meliOS is working...", 0x0D, 0x0A, 0 ;
