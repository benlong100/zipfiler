*--------------------------------------
* PRODOS.S -- the MLI calls this program makes
*
* An MLI call is JSR $BF00 followed inline by a command byte and a pointer to
* a parameter block. It returns with the carry set and the error code in A if
* it failed. STA preserves the carry, so a caller can branch on it after the
* wrapper has stashed the code.
*--------------------------------------

*--------------------------------------
* ONLINEF -- every online volume into ONLBUF
*
* Unit 0 means "all devices". Each answer is sixteen bytes: the first holds
* the unit number in its high nibble and the length of the volume name in its
* low nibble, and the name follows in plain ASCII. A length of zero means that
* device could not be read, and the byte after it is the error code -- a drive
* with the door open, most often, which is a thing to report rather than a
* thing to stop for.
*--------------------------------------
ONLINEF      jsr   MLI
             dfb   $c5
             da    ONLPARM
             sta   MLIERR
             rts

ONLPARM      dfb   $02
             dfb   $00              ; unit 0: every online device
             da    ONLBUF

*--- 16 answers of 16 bytes
             dum   $0e00
ONLBUF       ds    256
             dend

             dum   $1410
MLIERR       ds    1                ; the code from the last MLI call
             dend
