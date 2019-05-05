
; -----------------------------------------------------------------------------
;   update channel specified by channel_data
; -----------------------------------------------------------------------------

update:
;       ---------------------------------------------------
;       GET SELECTED CHANNEL'S PARAMETERS (19 CLOCK CYCLES)
;       ---------------------------------------------------
        ldi XH, 1                               ; prepare pointer
        mov XL, channel_data                    ;
        ld phase_delta_l, X+                    ; load channel's data from SRAM to registers
        ld phase_delta_h, X+                    ;
        ld note_ptr_l, X+                       ;
        ld note_ptr_h, X+                       ;
        ld duration, X+                         ;
        ld parameters, X+                       ;
        ld volume, X+                           ;
        ld status, X                            ;

        clr tmp4                                ; equal to zero throughout this routine

;       ---------------------------------------------------------------
;       UPDATE AND CHECK DURATION
;       (15 CLOCK CYCLES TO APPLY_EFFECT / 3 CLOCK CYCLES TO CH_UPDATE)
;       ---------------------------------------------------------------
        dec duration                            ; decrease duration
        breq ch_update                          ; if duration has ended, get next note

        ldi tmp2, 3                             ; volume increase step
        mov tmp1, duration                      ; copy duration for testing
        cpi tmp1, 7                             ;

        brlo ch_fade_out                        ; if duration < 7: decrease volume
        rjmp ch_fade_in                         ; if duration > 7: increase volume

ch_fade_out:
        nop                                     ;
        mov tmp1, volume                        ;
        cpi tmp1, 8                             ; (min level = 8)
        breq no_vol_dec                         ; if at min level, do not decrease volume
        dec volume                              ; if not at min level, decrease volume by one
no_vol_dec:
        nop
        rjmp apply_effects                      ; proceed to effect application

ch_fade_in:
        mov tmp1, volume                        ;
        cpi tmp1, 15                            ; (max level = 15)
        breq no_vol_inc                         ; if at max level, do not increase volume
        add volume, tmp2                        ; if not at max level, increase volume by three
no_vol_inc:
        nop
        rjmp apply_effects                      ; proceed to effect application

;       ---------------------------------------------
;       UPDATE CHANNEL'S PARAMETERS (51 CLOCK CYCLES)
;       ---------------------------------------------
ch_update:
        mov ZL, note_ptr_l                      ; Z points to effect, duration and duty cycle of note
        mov ZH, note_ptr_h                      ;
        lpm                                     ; get first byte of data

        mov parameters, r0                      ; keep effects -- clear duration
        ldi tmp3, 0b11111000                    ;
        and parameters, tmp3                    ;

        ldi tmp3, 0b00000111                    ; keep duration -- without effects
        and r0, tmp3                            ;
        mov duration, r0                        ;

        adiw ZH:ZL, 1                           ; Z points to pitch of note
        lpm                                     ; get pointer to phase_delta table

        ldi tmp1, 146                           ; check if reached the end (for this channel)
        cp r0, tmp1                             ;
        brne not_at_the_end                     ;

at_the_end:
        clr tmp1                                ; clear phase delta
        mov phase_delta_h, tmp1                 ;
        mov phase_delta_l, tmp1                 ;

        ldi tmp1, 2                             ; decrease note pointer (stay here forever)
        sub note_ptr_l, tmp1                    ;
        sbc note_ptr_h, tmp4                    ;

        ldi tmp1, 255                           ; set a high (pseudo)duration to delay next update
        mov duration, tmp1                      ;

        cbr status, 1                           ; mark end of melody for this channel (stopped)

        mov volume, tmp4                        ; set volume to zero

        ldi tmp3, 4                             ; delay padding
        rcall delay                             ;

        rjmp update_end

not_at_the_end:
        ldi ZH, high(deltas*2)                  ;
        ldi ZL, low(deltas*2)                   ;
        add ZL, r0                              ; add phase_delta pointer to table starting address
        adc ZH, tmp4                            ;
        lpm                                     ; get phase delta high-byte for new_note
        mov phase_delta_h, r0                   ;
        adiw ZH:ZL, 1                           ;
        lpm                                     ; get phase delta low-byte for new_note
        mov phase_delta_l, r0                   ;

        ldi ZH, high(durations*2)               ;
        ldi ZL, low(durations*2)                ;

        mov tmp1, rythm                         ;
        add tmp1, duration                      ; add duration and rythm offsets

        add ZL, tmp1                            ; add total offset to table starting address
        adc ZH, tmp4                            ;
        lpm                                     ;
        mov duration, r0                        ; get "decoded" duration

        ldi tmp1, 9                             ; set initial volume level
        mov volume, tmp1                        ;

        ldi tmp3, 2                             ; advance note pointer
        add note_ptr_l, tmp3                    ; (prepare for next note)
        adc note_ptr_h, tmp4                    ;

        rjmp update_end

;       -------------------------------
;       APPLY EFFECTS (20 CLOCK CYCLES)
;       -------------------------------
apply_effects:
        mov tmp1, parameters                    ;
        ldi tmp3, 0b11000000                    ; get effect
        and tmp1, tmp3                          ;
        breq effect_end                         ; jump to effect_end if no effect is selected

        cpi tmp1, 192                           ; check if [11-000000]: vibrato
        breq vibrato                            ;
        cpi tmp1, 128                           ; check if [10-000000]: pitch bend down
        breq pitch_bend_down                    ;
        cpi tmp1, 64                            ; check if [01-000000]: pitch bend up
        breq pitch_bend_up                      ;

vibrato: ; ------------------------------------
        mov tmp1, duration                      ;
        ldi tmp3, 0b00001100                    ;
        and tmp1, tmp3                          ; keep 3rd and 4th duration bits
        tst tmp1                                                        ;
        breq vibrato_add1                       ; if duration = xxxx00xx -> vibrato_add
        cpi tmp1, 12                            ;
        breq vibrato_add2                       ; if duration = xxxx11xx -> vibrato_add
        rjmp vibrato_sub                        ; else -> vibrato_sub
vibrato_add1:
        nop_x2                                  ;
vibrato_add2:
        adiw phase_delta_h:phase_delta_l, 20    ; 2
        ldi tmp3, 4                             ; 1
        rcall delay                             ; 19
        rjmp update_end                         ; 2
vibrato_sub:
        sbiw phase_delta_h:phase_delta_l, 20    ;
        ldi tmp3, 3                             ;
        rcall delay                             ;
        nop_x2                                  ;
        rjmp update_end                         ;

pitch_bend_down: ; ----------------------------
        sbiw phase_delta_h:phase_delta_l, 1     ;
        ldi tmp3, 6                             ;
        rcall delay                             ;
        rjmp update_end                         ;

pitch_bend_up: ; ------------------------------
        adiw phase_delta_h:phase_delta_l, 1     ;
        ldi tmp3, 5                             ;
        rcall delay                             ;
        nop_x2                                  ;
        rjmp update_end                         ;

effect_end:     ; ---------------------------------
        ldi tmp3, 8                             ; delay padding
        rcall delay                             ;
        nop_x2                                  ;

;       ----------------------------------------------------
;       SAVE SELECTED CHANNEL'S PARAMETERS (22 CLOCK CYCLES)
;       ----------------------------------------------------
update_end:
        ldi XH, 1                               ; prepare pointer
        mov XL, channel_data                    ;
        st X+, phase_delta_l                    ; copy channel's data from registers to SRAM
        st X+, phase_delta_h                    ;
        st X+, note_ptr_l                       ;
        st X+, note_ptr_h                       ;
        st X+, duration                         ;
        st X+, parameters                       ;
        st X+, volume                           ;
        st X, status                            ;
        ret
