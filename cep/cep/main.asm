.INCLUDE "m32def.inc"
.ORG 0x00

.DEF temp = r16
.DEF command = r17
.DEF data = r18
.DEF result = r19
.DEF count = r20
.DEF dummy = r21
.DEF humi = r22
.DEF duty = r23
.DEF current_reading = r24
.DEF overload_counter = r25
.DEF zone_flag = r26

.EQU RS = 0
.EQU E = 1
.EQU DHT11 = 2    
.EQU AIN1 = 0       
.EQU AIN2 = 1       
.EQU STBY = 1       
.EQU PWMA = 7  
.EQU BIN1 = 2           
.EQU BIN2 = 3          
.EQU PWMB = 3           
.EQU GAS  = 4
.EQU CURRENT_SENSOR = 0

; Zone thresholds
.EQU SAFE_CURRENT = 50
.EQU RISK_CURRENT = 65
.EQU DANGER_CURRENT = 70
.EQU OVERLOAD_DELAY = 3

MAIN:
    RCALL EEPROM_Increment      
    
    ; Initialize ports
    LDI temp, (1<<RS)|(1<<E)|(1<<PWMB)
    OUT DDRB, temp              
    LDI temp, (1<<AIN1)|(1<<AIN2)|(1<<BIN1)|(1<<BIN2)|(1<<PWMA)
    OUT DDRD, temp
    CBI DDRD, GAS
    SBI PORTD, GAS

    ; ? FIXED ADC Setup - Clear channel selection
    LDI temp, (1<<REFS0)|(0)  ; ADC0 channel explicitly
    OUT ADMUX, temp
    LDI temp, (1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)
    OUT ADCSRA, temp

    LDI temp, (1<<STBY)
    OUT DDRA, temp
    SBI PORTA, STBY        
    
    ; LCD Initialization with LONG delays
    RCALL delay200ms
    RCALL delay200ms
    RCALL delay200ms

    ; LCD Setup with proper delays
    LDI command, 0x38
    RCALL send_command
    RCALL delay20ms
    
    LDI command, 0x38
    RCALL send_command
    RCALL delay10ms
    
    LDI command, 0x38
    RCALL send_command
    RCALL delay10ms
    
    LDI command, 0x0E
    RCALL send_command
    RCALL delay10ms
    
    LDI command, 0x01
    RCALL send_command
    RCALL delay50ms

    ; Motor PWM Setup - PRESCALER 8
    LDI temp, (1<<WGM20)|(1<<COM21)|(1<<CS21)  ; Prescaler 8
    OUT TCCR2, temp
    LDI duty, 220
    OUT OCR2, duty

    LDI temp, (1<<WGM00)|(1<<COM01)|(1<<CS01)  ; Prescaler 8  
    OUT TCCR0, temp
    LDI duty, 220
    OUT OCR0, duty

    ; Initialize variables
    LDI overload_counter, 0
    LDI zone_flag, 0

    ; Start Motors at Good Speed
    CBI PORTD, AIN1
    SBI PORTD, AIN2
    SBI PORTD, BIN1
    CBI PORTD, BIN2

; MAIN LOOP
main_loop:
    ; ? FIXED: Current monitoring with proper ADC read
    RCALL Read_Current
    RCALL Check_Current_Zone
    RCALL Handle_Current_Condition

    ; Check if system is in overload state
    SBRC zone_flag, 7
    RJMP overload_detected

    ; Read DHT11
    RCALL Request
    RCALL Response
    RCALL Receive_Data
    MOV humi, result
    RCALL Receive_Data
    RCALL Receive_Data
    MOV temp, result
    RCALL Receive_Data
    RCALL Receive_Data

    ; Update Display with LONG delay
    RCALL Update_Display
    RCALL delay2s          ; 2 seconds delay after display update

    ; Process modes
    CPI temp, 15
    BRLO HEAT_MODE
    CPI temp, 25
    BRSH COOL_MODE
    RJMP STABLE_MODE

HEAT_MODE:
    CBI PORTD, AIN1
    SBI PORTD, AIN2

    CPI temp, 10
    BRLO heat_full
    CPI temp, 13
    BRLO heat_high
    RJMP heat_med

heat_full:
    LDI duty, 250    ; 98% speed
    OUT OCR2, duty
    RJMP FAN_UPDATE
heat_high:
    LDI duty, 220    ; 86% speed
    OUT OCR2, duty
    RJMP FAN_UPDATE
heat_med:
    LDI duty, 180    ; 70% speed
    OUT OCR2, duty
    RJMP FAN_UPDATE

COOL_MODE:
    SBI PORTD, AIN1
    CBI PORTD, AIN2

    CPI temp, 30
    BRSH cool_full
    CPI temp, 28
    BRSH cool_high
    RJMP cool_med

cool_full:
    LDI duty, 250    ; 98% speed
    OUT OCR2, duty
    RJMP FAN_UPDATE
cool_high:
    LDI duty, 220    ; 86% speed
    OUT OCR2, duty
    RJMP FAN_UPDATE
cool_med:
    LDI duty, 180    ; 70% speed
    OUT OCR2, duty
    RJMP FAN_UPDATE

STABLE_MODE:
    CBI PORTD, AIN1
    CBI PORTD, AIN2
    LDI duty, 0
    OUT OCR2, duty
    RJMP FAN_UPDATE
    
FAN_UPDATE:
    SBIC PIND, GAS
    RJMP GAS_DETECTED      
    
    CPI humi, 60
    BRLO Fan_Low    
    CPI humi, 80
    BRLO Fan_Med 
    
Fan_Full:
    SBI PORTD, BIN1
    CBI PORTD, BIN2
    LDI duty, 250    ; 98% speed
    OUT OCR0, duty
    RJMP main_loop
    
GAS_DETECTED:
    SBI PORTD, BIN1
    CBI PORTD, BIN2
    LDI duty, 255    ; 100% speed
    OUT OCR0, duty
    RJMP main_loop

Fan_Med:
    SBI PORTD, BIN1
    CBI PORTD, BIN2
    LDI duty, 200    ; 78% speed
    OUT OCR0, duty
    RJMP main_loop

Fan_Low:
    SBI PORTD, BIN1
    CBI PORTD, BIN2
    LDI duty, 150    ; 59% speed
    OUT OCR0, duty
    RJMP main_loop

; OVERLOAD DETECTED - NEW FUNCTION
overload_detected:
    RCALL lcd_clear
    LDI data, 'C'
    RCALL send_data
    LDI data, 'U'
    RCALL send_data
    LDI data, 'R'
    RCALL send_data
    LDI data, 'R'
    RCALL send_data
    LDI data, 'E'
    RCALL send_data
    LDI data, 'N'
    RCALL send_data
    LDI data, 'T'
    RCALL send_data
    LDI data, ' '
    RCALL send_data
    LDI data, 'O'
    RCALL send_data
    LDI data, 'V'
    RCALL send_data
    LDI data, 'E'
    RCALL send_data
    LDI data, 'R'
    RCALL send_data
    LDI data, 'L'
    RCALL send_data
    LDI data, 'O'
    RCALL send_data
    LDI data, 'A'
    RCALL send_data
    LDI data, 'D'
    RCALL send_data
    
    LDI command, 0xC0
    RCALL send_command
    LDI data, 'S'
    RCALL send_data
    LDI data, 'P'
    RCALL send_data
    LDI data, 'E'
    RCALL send_data
    LDI data, 'E'
    RCALL send_data
    LDI data, 'D'
    RCALL send_data
    LDI data, ' '
    RCALL send_data
    LDI data, 'R'
    RCALL send_data
    LDI data, 'E'
    RCALL send_data
    LDI data, 'D'
    RCALL send_data
    LDI data, 'U'
    RCALL send_data
    LDI data, 'C'
    RCALL send_data
    LDI data, 'E'
    RCALL send_data
    LDI data, 'D'
    RCALL send_data
    
    RCALL delay2s
    RJMP main_loop

; ? FIXED ADC READING - PROPER WAY
Read_Current:
    ; Start conversion
    LDI temp, (1<<ADEN)|(1<<ADSC)|(1<<ADPS2)|(1<<ADPS1)
    OUT ADCSRA, temp
    
    ; Wait for conversion to complete
Wait_ADC:
    SBIC ADCSRA, ADSC
    RJMP Wait_ADC
    
    ; ? MUST READ ADCL FIRST, THEN ADCH
    IN current_reading, ADCL    ; Read low byte FIRST
    IN temp, ADCH               ; Read high byte SECOND
    
    ; For testing - manual value (comment out when using actual ADC)
    ; LDI current_reading, 65   ; Testing ke liye
    
    RET

Check_Current_Zone:
    ; ? Now current_reading contains actual ADC value
    CPI current_reading, DANGER_CURRENT
    BRSH Set_Danger_Zone
    CPI current_reading, RISK_CURRENT
    BRSH Set_Risk_Zone
    LDI zone_flag, 0x00
    RET

Set_Danger_Zone:
    LDI zone_flag, 0x03
    RET

Set_Risk_Zone:
    LDI zone_flag, 0x02
    RET

Handle_Current_Condition:
    CPI zone_flag, 0x03
    BREQ Increment_Overload_Counter
    CPI zone_flag, 0x02
    BREQ Increment_Overload_Counter
    
    LDI overload_counter, 0
    CBR zone_flag, 0x80  ; Clear overload flag
    RET

Increment_Overload_Counter:
    INC overload_counter
    CPI overload_counter, OVERLOAD_DELAY
    BRLO No_Overload_Yet
    
    ; Overload detected - reduce speed and set flag
    RCALL Reduce_Speed
    SBR zone_flag, 0x80  ; Set overload flag (bit 7)
    LDI overload_counter, 0
    RET
    
No_Overload_Yet:
    RET

Reduce_Speed:
    IN duty, OCR2
    CPI duty, 80
    BRLO Skip_Motor_Reduction
    SUBI duty, 80
    OUT OCR2, duty

    IN duty, OCR0
    CPI duty, 80
    BRLO Skip_Fan_Reduction
    SUBI duty, 80
    OUT OCR0, duty
    
Skip_Fan_Reduction:
Skip_Motor_Reduction:
    RET

; DISPLAY with MODE and CURRENT INFO
Update_Display:
    RCALL lcd_clear
    
    ; Line 1: Temperature + Mode
    LDI data, 'T'
    RCALL send_data
    RCALL delay100ms
    
    LDI data, '='
    RCALL send_data
    RCALL delay100ms
    
    MOV result, temp
    RCALL convert_to_ascii_slow
    RCALL delay100ms
    
    LDI data, 0xDF
    RCALL send_data
    RCALL delay100ms
    
    LDI data, 'C'
    RCALL send_data
    RCALL delay100ms
    
    LDI data, ' '
    RCALL send_data
    RCALL delay100ms
    
    ; Show mode
    CPI temp, 15
    BRLO show_heating
    CPI temp, 25
    BRSH show_cooling
    
    LDI data, 'S'
    RCALL send_data
    LDI data, 'T'
    RCALL send_data
    LDI data, 'B'
    RCALL send_data
    RJMP line1_done
    
show_heating:
    LDI data, 'H'
    RCALL send_data
    LDI data, 'T'
    RCALL send_data
    LDI data, 'G'
    RCALL send_data
    RJMP line1_done
    
show_cooling:
    LDI data, 'C'
    RCALL send_data
    LDI data, 'L'
    RCALL send_data
    LDI data, 'G'
    RCALL send_data
    
line1_done:
    ; Line 2: Humidity + Current
    LDI command, 0xC0
    RCALL send_command
    RCALL delay100ms
    
    LDI data, 'H'
    RCALL send_data
    RCALL delay100ms
    
    LDI data, '='
    RCALL send_data
    RCALL delay100ms
    
    MOV result, humi
    RCALL convert_to_ascii_slow
    RCALL delay100ms
    
    LDI data, '%'
    RCALL send_data
    RCALL delay100ms
    
  
    
    RET

; SLOW LCD ROUTINES with LONG delays
lcd_clear:
    LDI command, 0x01
    RCALL send_command
    RCALL delay200ms
    RET

send_command:
    OUT PORTC, command
    CBI PORTB, RS
    SBI PORTB, E
    RCALL delay5ms
    CBI PORTB, E
    RCALL delay20ms
    RET

send_data:
    OUT PORTC, data
    SBI PORTB, RS
    SBI PORTB, E
    RCALL delay5ms
    CBI PORTB, E
    RCALL delay20ms
    RET

convert_to_ascii_slow:
    LDI dummy, 0
TenLoop_slow:
    CPI result, 10
    BRLO OneDigit_slow
    SUBI result, 10
    INC dummy
    RJMP TenLoop_slow
OneDigit_slow:
    LDI data, '0'
    ADD data, dummy
    RCALL send_data
    RCALL delay100ms
    
    LDI data, '0'
    ADD data, result
    RCALL send_data
    RCALL delay100ms
    RET

; DELAY ROUTINES
delay2s:
    LDI r22, 20
outer_2s:
    LDI r23, 100
mid_2s:
    LDI r24, 200
inner_2s:
    DEC r24
    BRNE inner_2s
    DEC r23
    BRNE mid_2s
    DEC r22
    BRNE outer_2s
    RET

delay200ms:
    LDI r24, 200
d1_200:
    LDI r25, 250
d2_200:
    DEC r25
    BRNE d2_200
    DEC r24
    BRNE d1_200
    RET

delay100ms:
    LDI r24, 100
d1_100:
    LDI r25, 250
d2_100:
    DEC r25
    BRNE d2_100
    DEC r24
    BRNE d1_100
    RET

delay50ms:
    LDI r24, 100
d1_50:
    LDI r25, 250
d2_50:
    DEC r25
    BRNE d2_50
    DEC r24
    BRNE d1_50
    RET

delay20ms:
    LDI r24, 40
d1_20:
    LDI r25, 250
d2_20:
    DEC r25
    BRNE d2_20
    DEC r24
    BRNE d1_20
    RET

delay10ms:
    LDI r24, 20
d1_10:
    LDI r25, 250
d2_10:
    DEC r25
    BRNE d2_10
    DEC r24
    BRNE d1_10
    RET

delay5ms:
    LDI r24, 10
d1_5:
    LDI r25, 250
d2_5:
    DEC r25
    BRNE d2_5
    DEC r24
    BRNE d1_5
    RET

; DHT11 ROUTINES 
Request:
    SBI DDRA, DHT11
    CBI PORTA, DHT11
    RCALL delay20ms
    SBI PORTA, DHT11
    RET

Response:
    CBI DDRA, DHT11
Wait_Low1:
    SBIC PINA, DHT11
    RJMP Wait_Low1
Wait_High1:
    SBIS PINA, DHT11
    RJMP Wait_High1
Wait_Low2:
    SBIC PINA, DHT11
    RJMP Wait_Low2
    RET

Receive_Data:
    CLR result
    LDI count, 8
Read_Loop:
Wait_BitStart:
    SBIC PINA, DHT11
    RJMP Wait_BitStart
Wait_High:
    SBIS PINA, DHT11
    RJMP Wait_High
    RCALL delay_30us
    SBIC PINA, DHT11
    RJMP Bit_High
Bit_Low:
    LSL result
    RJMP Bit_Done
Bit_High:
    LSL result
    ORI result, 0x01
Bit_Done:
Wait_End:
    SBIC PINA, DHT11
    RJMP Wait_End
    DEC count
    BRNE Read_Loop
    RET

delay_30us:
    LDI r25, 10
d30:
    DEC r25
    BRNE d30
    RET

; EEPROM COUNTER
EEPROM_Increment:
EEWait:
    SBIC EECR, EEWE
    RJMP EEWait
    LDI R16, 0x00
    OUT EEARH, R16
    OUT EEARL, R16
    SBI EECR, EERE
    IN R17, EEDR
    INC R17
    OUT EEDR, R17
    LDI R16, 0x00
    OUT EEARH, R16
    OUT EEARL, R16
    SBI EECR, EEMWE
    SBI EECR, EEWE
WaitWrite:
    SBIC EECR, EEWE
    RJMP WaitWrite
    RET