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

*--------------------------------------
* OPENF / READF / CLOSEF -- reading a directory as a file
*
* A directory IS a file, so it opens and reads like one: 512 bytes a block,
* four bytes of links then thirteen entries of thirty-nine.
*--------------------------------------
OPENF        jsr   MLI
             dfb   $c8
             da    OPENPARM
             sta   MLIERR
             rts

READF        jsr   MLI
             dfb   $ca
             da    READPARM
             sta   MLIERR
             rts

CLOSEF       jsr   MLI
             dfb   $cc
             da    CLOSEPARM
             sta   MLIERR
             rts

OPENPARM     dfb   $03
             da    PATHBUF          ; length-prefixed, LOW ascii
             da    IOBUF            ; 1K, page aligned, ProDOS scribbles here
OPENREF      dfb   $00              ; out: the reference number

READPARM     dfb   $04
READREF      dfb   $00
             da    DIRBUF
             da    $0200            ; one directory block
XFERCNT      ds    2                ; out: how much actually came back

CLOSEPARM    dfb   $01
CLOSEREF     dfb   $00

*--- ProDOS wants its own 1K buffer page-aligned, and one directory block to
*    read into. Neither is ours to put anywhere else.
             dum   $0800
IOBUF        ds    1024
DIRBUF       ds    512
             dend

*--- A pathname: a length byte then up to 64 characters, low ASCII, which is
*    the one place on this machine where the high bit stays off.
             dum   $1420
PATHBUF      ds    65
             dend
