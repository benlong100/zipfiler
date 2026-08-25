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

*--- $1400-$1410 is filer.S's; tools/dumcheck.py keeps these honest
             dum   $1418
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
             da    PATH0            ; SELPANEL aims this at the panel being
                                    ; read; the value here is only a start
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
IOBUF        ds    1024             ; the source of a copy, and directories
DIRBUF       ds    512
             dend

*--- the destination of a copy, page aligned as ProDOS insists
             dum   $1000
IOBUF2       ds    1024
             dend

*--- and what is carried between them. Auxiliary memory belongs to /RAM here
*    -- design.md section 8 -- so this lives in main, above the panels.
COPYSIZE     equ   $2000
             dum   $8000
COPYBUF      ds    COPYSIZE
             dend

*--------------------------------------
* GINFOF / SINFOF -- read and write a file's attributes
*
* The two parameter lists overlap but are NOT the same shape. GET_FILE_INFO
* returns storage type and blocks used in the three bytes that SET_FILE_INFO
* requires to be zero -- so they are kept as separate blocks and the fields
* that carry over are copied across deliberately. Sharing one block would
* write a file's block count into a reserved field, which is the kind of
* mistake that is invisible until a directory is unreadable.
*--------------------------------------
*--------------------------------------
* The calls a copy makes. It has both files open at once, so the source and
* the destination each need their own 1K buffer and their own parameter
* blocks -- sharing them would mean rebuilding one between every read and
* every write.
*--------------------------------------
CREATEF      jsr   MLI
             dfb   $c0
             da    CREPARM
             sta   MLIERR
             rts

COPENSF      jsr   MLI
             dfb   $c8
             da    COPENS
             sta   MLIERR
             rts

COPENDF      jsr   MLI
             dfb   $c8
             da    COPEND
             sta   MLIERR
             rts

CREADF       jsr   MLI
             dfb   $ca
             da    CREADP
             sta   MLIERR
             rts

CWRITEF      jsr   MLI
             dfb   $cb
             da    CWRITEP
             sta   MLIERR
             rts

CCLOSEF      jsr   MLI
             dfb   $cc
             da    CCLOSEP
             sta   MLIERR
             rts

CREPARM      dfb   $07
             da    PATHNEW
CREACCESS    dfb   $c3
CRETYPE      dfb   $00
CREAUX       dfb   $00,$00
CRESTORE     dfb   $01              ; seedling; ProDOS grows it as needed
CREDATE      dfb   $00,$00
CRETIME      dfb   $00,$00

COPENS       dfb   $03
             da    PATHWORK
             da    IOBUF
SRCREF       dfb   $00

COPEND       dfb   $03
             da    PATHNEW
             da    IOBUF2
DSTREF       dfb   $00

CREADP       dfb   $04
CREADREF     dfb   $00
             da    COPYBUF
             da    COPYSIZE
CGOT         dfb   $00,$00

CWRITEP      dfb   $04
CWRITEREF    dfb   $00
             da    COPYBUF
CWANT        dfb   $00,$00
CPUT         dfb   $00,$00

CCLOSEP      dfb   $01
CCLOSEREF    dfb   $00

DESTROYF     jsr   MLI
             dfb   $c1
             da    DESTPARM
             sta   MLIERR
             rts

DESTPARM     dfb   $01
             da    PATHWORK

RENAMEF      jsr   MLI
             dfb   $c2
             da    RENPARM
             sta   MLIERR
             rts

*--- ProDOS renames within a directory: both paths name the same parent.
RENPARM      dfb   $02
             da    PATHWORK         ; what it is called now
             da    PATHNEW          ; and what it is to be called

GINFOF       jsr   MLI
             dfb   $c4
             da    GINFOPARM
             sta   MLIERR
             rts

SINFOF       jsr   MLI
             dfb   $c3
             da    SINFOPARM
             sta   MLIERR
             rts

GINFOPARM    dfb   $0a
             da    PATHWORK
GACCESS      dfb   $00
GTYPE        dfb   $00
GAUX         dfb   $00,$00
GSTORE       dfb   $00
GBLOCKS      dfb   $00,$00
GMODD        dfb   $00,$00
GMODT        dfb   $00,$00
GCRED        dfb   $00,$00
GCRET        dfb   $00,$00

SINFOPARM    dfb   $07
             da    PATHWORK
SACCESS      dfb   $00
STYPE        dfb   $00
SAUX         dfb   $00,$00
             dfb   $00,$00,$00      ; reserved, and it must stay zero
SMODD        dfb   $00,$00
SMODT        dfb   $00,$00

*--- A pathname: a length byte then up to 64 characters, low ASCII, which is
*    the one place on this machine where the high bit stays off. PATHWORK is
*    the full path of one entry, built when a command needs to name it.
             dum   $1420
PATHWORK     ds    65
             dend
