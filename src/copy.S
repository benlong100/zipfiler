*--------------------------------------
* COPY.S -- C, always from the left panel to the right
*
* The direction is fixed so that it never has to be expressed; when something
* has to go the other way, S exchanges the panels. See design.md section 5.
*
* Everything here is written so that a failure leaves nothing behind. A copy
* that stops halfway leaves a truncated file on the destination with a
* plausible name and the right type, which is worse than no copy at all
* because it looks like it worked -- so a copy that fails destroys its own
* output before it reports. The free space check is deferred (section 11);
* handling the failure is not.
*--------------------------------------

*--------------------------------------
* CPYCMD -- copy what the command applies to
*--------------------------------------
CPYCMD       lda   #$00
             sta   OVERW            ; nothing decided about overwriting yet
             sta   NDONE
             sta   NSKIP
             sta   NFAIL

*--- The same directory in both panels would mean copying a file onto itself.
*    Easy to arrange, and nothing good comes of it.
             jsr   SAMEDIR
             bcc   :start
             lda   #<MSAMEDIR
             ldy   #>MSAMEDIR
             jmp   SAYTEXT

:start       lda   #$00
             jsr   SELPANEL         ; targets always come from the left
             jsr   TGTINIT
:each        jsr   TGTNEXT
             bcs   :done

*--- a directory needs the recursion that is not built yet, and says so
*    rather than half-copying itself
             ldy   TGTI
             lda   (PTYPE),y
             cmp   #$0f
             bne   :file
             inc   NSKIP
             jmp   :next

:file        jsr   CPYPATHS
             jsr   CPYONE
             bcc   :ok
             lda   CPYSTOP
             bne   :done            ; the writer asked to stop
             jmp   :next
:ok          inc   NDONE
:next        lda   #$00
             jsr   SELPANEL         ; CPYPATHS left the right panel chosen
             jmp   :each

:done        lda   #$01             ; the destination listing has changed
             jsr   SELPANEL
             jsr   RESCAN
             jsr   CLAMPSEL
             lda   #$00
             jsr   SELPANEL
             jmp   CPYSAY

*--------------------------------------
* CPYPATHS -- PATHWORK = the source, PATHNEW = where it is going
*
* NAMPTR is an address in the left panel's names, so it survives choosing the
* right panel: the name comes from one side and the directory from the other.
*--------------------------------------
CPYPATHS     lda   TGTI
             jsr   PATHENT          ; the left panel's directory and the name
             lda   #$01
             jsr   SELPANEL
             lda   #<PATHNEW
             sta   PBUF
             lda   #>PATHNEW
             sta   PBUF+1
             jmp   PATHBLD          ; the right panel's directory, same name

*--------------------------------------
* SAMEDIR -- carry set if both panels are looking at the same directory
*--------------------------------------
SAMEDIR      ldy   PATH0
             cpy   PATH1
             bne   :no
             cpy   #$00
             beq   :yes             ; both empty: both the volume list
:loop        lda   PATH0,y
             cmp   PATH1,y
             bne   :no
             dey
             bne   :loop
:yes         sec
             rts
:no          clc
             rts

*--------------------------------------
* CPYONE -- one file from PATHWORK to PATHNEW. Carry set if it did not go.
*--------------------------------------
CPYONE       lda   #$00
             sta   CPYSTOP

*--- what it is, so that what arrives is the same thing
             jsr   GINFOF
             bcc   *+5
             jmp   :bad
             lda   GACCESS
             sta   CREACCESS
             lda   GTYPE
             sta   CRETYPE
             lda   GAUX
             sta   CREAUX
             lda   GAUX+1
             sta   CREAUX+1
             lda   GCRED
             sta   CREDATE
             lda   GCRED+1
             sta   CREDATE+1
             lda   GCRET
             sta   CRETIME
             lda   GCRET+1
             sta   CRETIME+1

*--- an unlocked destination, whatever the source was; the access is put back
*    at the end, once there is something to protect
             lda   CREACCESS
             ora   #$c2
             sta   CREACCESS

:make        jsr   CREATEF
             bcc   :opened
             lda   MLIERR
             cmp   #$47             ; there is one there already
             beq   :exists
             jmp   :bad2

*--- Asked once for the whole batch, not once a file: right for one file and
*    miserable for twelve. design.md section 7.
:exists      lda   OVERW
             bne   :decided
             jsr   ASKOVER
:decided     lda   OVERW
             cmp   #$02             ; skip everything that is already there
             bne   *+5
             jmp   :skipped
             cmp   #$03             ; stop altogether
             bne   *+5
             jmp   :stop
             jsr   DESTNEW          ; overwrite: take the old one away first
             bcc   *+5
             jmp   :bad2
             jmp   :make

:bad2        jmp   :bad

:opened      jsr   COPENSF
             bcs   :undo
             lda   SRCREF
             sta   CREADREF
             jsr   COPENDF
             bcs   :shutsrc
             lda   DSTREF
             sta   CWRITEREF

:move        jsr   CREADF
             bcs   :fin             ; the end of the file arrives as an error
             lda   CGOT
             ora   CGOT+1
             beq   :fin
             lda   CGOT
             sta   CWANT
             lda   CGOT+1
             sta   CWANT+1
             jsr   CWRITEF
             bcs   :wfail
             jmp   :move

:fin         jsr   SHUTBOTH
*--- and now the dates and the access the source had
             lda   GTYPE
             sta   STYPE
             lda   GAUX
             sta   SAUX
             lda   GAUX+1
             sta   SAUX+1
             lda   GMODD
             sta   SMODD
             lda   GMODD+1
             sta   SMODD+1
             lda   GMODT
             sta   SMODT
             lda   GMODT+1
             sta   SMODT+1
             lda   GACCESS
             sta   SACCESS
             jsr   SETNEW
             clc
             rts

*--- a write that failed leaves a plausible-looking file that is not the file
:wfail       jsr   SHUTBOTH
             jsr   DESTNEW
             inc   NFAIL
             sec
             rts

:shutsrc     lda   SRCREF
             sta   CCLOSEREF
             jsr   CCLOSEF
:undo        jsr   DESTNEW
:bad         inc   NFAIL
             sec
             rts

:skipped     inc   NSKIP
             sec
             rts
:stop        lda   #$01
             sta   CPYSTOP
             sec
             rts

*--------------------------------------
* SHUTBOTH -- close the two files, whatever happened
*--------------------------------------
SHUTBOTH     lda   SRCREF
             sta   CCLOSEREF
             jsr   CCLOSEF
             lda   DSTREF
             sta   CCLOSEREF
             jmp   CCLOSEF

*--- DESTNEW / SETNEW -- act on PATHNEW rather than on PATHWORK
DESTNEW      lda   #<PATHNEW
             sta   DESTPARM+1
             lda   #>PATHNEW
             sta   DESTPARM+2
             jsr   DESTROYF
             pha
             lda   #<PATHWORK       ; and put it back, for D
             sta   DESTPARM+1
             lda   #>PATHWORK
             sta   DESTPARM+2
             pla
             rts

SETNEW       lda   #<PATHNEW
             sta   SINFOPARM+1
             lda   #>PATHNEW
             sta   SINFOPARM+2
             jsr   SINFOF
             pha
             lda   #<PATHWORK
             sta   SINFOPARM+1
             lda   #>PATHWORK
             sta   SINFOPARM+2
             pla
             rts

*--------------------------------------
* ASKOVER -- once for the batch: overwrite, skip them, or stop
*--------------------------------------
ASKOVER      jsr   CLRBUF
             lda   #<MOVER
             ldy   #>MOVER
             jsr   SETSTR
             jsr   CENTRE
             jsr   BUFSTR
             jsr   INVBUF
             lda   #STATROW
             jsr   DRAWLINE
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             lda   KEYCHR
             cmp   #$9b             ; ESC stops, as everywhere else
             beq   :stop
             and   #$df
             cmp   #$cf             ; O: overwrite them
             beq   :over
             cmp   #$d3             ; S: skip the ones already there
             beq   :skip
             jmp   :key
:over        lda   #$01
             sta   OVERW
             rts
:skip        lda   #$02
             sta   OVERW
             rts
:stop        lda   #$03
             sta   OVERW
             rts

*--------------------------------------
* CPYSAY -- what happened
*--------------------------------------
CPYSAY       lda   NFAIL
             beq   :nofail
             sta   MSGN
             lda   #<MCPYFAIL
             ldy   #>MCPYFAIL
             jmp   SAYMSG
:nofail      lda   NSKIP
             beq   :plain
             lda   NDONE
             sta   MSGN
             lda   #<MCPYSOME
             ldy   #>MCPYSOME
             jmp   SAYMSG
:plain       lda   NDONE
             sta   MSGN
             lda   #<MCOPIED
             ldy   #>MCOPIED
             jmp   SAYMSG

MSAMEDIR     asc   "both panels are the same directory"
             dfb   $00
MOVER        asc   "already there.  O verwrite, S kip, ESC to stop"
             dfb   $00
MCOPIED      asc   "copied"
             dfb   $00
MCPYSOME     asc   "copied; the rest were skipped"
             dfb   $00
MCPYFAIL     asc   "could not be copied"
             dfb   $00

*--- $1480-$1490 is catalog.S's; dumcheck.py caught the collision
             dum   $1492
OVERW        ds    1                ; what was decided about existing files
CPYSTOP      ds    1                ; the writer asked to stop
             dend
