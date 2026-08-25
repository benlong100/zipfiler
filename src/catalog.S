*--------------------------------------
* CATALOG.S -- what a panel has read, and how it is held
*
* Parallel arrays rather than records: names in a block of 16-byte stride,
* everything else in an array of its own. Indexing a 16-byte stride is a
* shift rather than a multiply, and nothing is padded. See design.md §4.
*
* Names are held as ProDOS gives them -- plain, low ASCII -- because that is
* what has to go back into a pathname. Bit 7 goes on at the screen.
*
* Every routine here works on whichever panel SELPANEL last chose, so none of
* it is written twice.
*--------------------------------------
MAXENT       equ   255              ; per panel, and a count that fits a byte

*--------------------------------------
* SELPANEL -- A = 0 or 1. Point the working pointers at that panel.
*
* Also aims the MLI open at that panel's pathname, so a scan reads the path
* belonging to the panel it is filling.
*--------------------------------------
SELPANEL     sta   PANSEL
             tax
             lda   PANBASE,x
             sta   PNAMES
             sta   PTYPE
             sta   PBLKLO
             sta   PBLKHI
             sta   PACC
             lda   PANBASE+2,x
             sta   PNAMES+1
             clc
             adc   #>OFFTYPE
             sta   PTYPE+1
             clc
             adc   #$01
             sta   PBLKLO+1
             clc
             adc   #$01
             sta   PBLKHI+1
             clc
             adc   #$01
             sta   PACC+1

*--- and the path this panel is showing
             lda   PATHLO,x
             sta   OPENPARM+1
             sta   PATHPTR
             lda   PATHHI,x
             sta   OPENPARM+2
             sta   PATHPTR+1

*--- and its tags
             lda   TAGLO,x
             sta   PTAGS
             lda   TAGHI,x
             sta   PTAGS+1
             rts

PANBASE      dfb   <PAN0,<PAN1
             dfb   >PAN0,>PAN1
PATHLO       dfb   <PATH0,<PATH1
PATHHI       dfb   >PATH0,>PATH1
TAGLO        dfb   <TAGS0,<TAGS1
TAGHI        dfb   >TAGS0,>TAGS1

*--------------------------------------
* NAMEAT -- NAMPTR = the name of entry A in the chosen panel
*--------------------------------------
NAMEAT       sta   TMPA
             lda   #$00
             sta   TMPC
             ldx   #$04
:shift       asl   TMPA
             rol   TMPC
             dex
             bne   :shift
             lda   TMPA
             clc
             adc   PNAMES
             sta   NAMPTR
             lda   TMPC
             adc   PNAMES+1
             sta   NAMPTR+1
             rts

*--------------------------------------
* VOLSCAN -- fill the chosen panel from the list of online volumes
*
* The volume list is what "up from a root" reaches, so it is a listing like
* any other and goes in the same arrays.
*
* An ONLBUF answer and a cached name have the same shape -- a length byte
* then the characters -- so pointing at both and using one index copies one
* into the other with nothing to adjust.
*--------------------------------------
VOLSCAN      jsr   SAYWORK          ; reading a device list is not instant
             jsr   TAGNONE          ; tags belong to a listing, not to a panel
             jsr   ONLINEF
             ldx   PANSEL
             lda   #$00
             sta   PCOUNT,x
             sta   IDX

:each        lda   IDX
             asl                    ; each answer is sixteen bytes
             asl
             asl
             asl
             clc
             adc   #<ONLBUF
             sta   ENTPTR
             lda   #>ONLBUF
             adc   #$00
             sta   ENTPTR+1

             ldy   #$00
             lda   (ENTPTR),y
             and   #$0f             ; the name length; zero is a device that
             beq   :next            ; could not be read, so it is not listed
             sta   TMPB

             ldx   PANSEL
             lda   PCOUNT,x
             jsr   NAMEAT
             lda   TMPB
             ldy   #$00
             sta   (NAMPTR),y
:copy        iny
             lda   (ENTPTR),y
             sta   (NAMPTR),y
             cpy   TMPB
             bcc   :copy

*--- a volume is not a file: no type of its own, and nothing to unlock
             ldx   PANSEL
             ldy   PCOUNT,x
             lda   #TYPVOL
             sta   (PTYPE),y
             lda   #$02             ; write-enable set, so it draws unlocked
             sta   (PACC),y
             lda   #$00
             sta   (PBLKLO),y
             sta   (PBLKHI),y
             inc   PCOUNT,x

:next        inc   IDX
             lda   IDX
             cmp   #16
             bcc   :each
             rts

*--------------------------------------
* DIRSCAN -- read the directory named by the chosen panel's path
*
* Carry set and MLIERR meaningful if it could not be read.
*--------------------------------------
DIRSCAN      jsr   SAYWORK          ; a floppy takes long enough to wonder
             jsr   TAGNONE          ; tags belong to a listing, not to a panel
             ldx   PANSEL
             lda   #$00
             sta   PCOUNT,x
             jsr   OPENF
             bcs   :fail
             lda   OPENREF
             sta   READREF
             sta   CLOSEREF

:block       jsr   READF
             bcs   :done            ; end of file arrives as an error, and
             lda   XFERCNT          ; means only that there are no more
             ora   XFERCNT+1
             beq   :done

*--- past the four link bytes, thirteen entries of thirty-nine
             lda   #<DIRBUF+4
             sta   ENTPTR
             lda   #>DIRBUF+4
             sta   ENTPTR+1
             lda   #$0d
             sta   ENTN

:entry       ldy   #$00
             lda   (ENTPTR),y
             beq   :next            ; never used, or since deleted
             lsr
             lsr
             lsr
             lsr                    ; the storage type
             cmp   #$0e
             bcs   :next            ; $E and $F are the directory's own header
             jsr   TAKEENT
             ldx   PANSEL
             lda   PCOUNT,x
             cmp   #MAXENT
             bcs   :shut            ; the cap in design.md section 4

:next        lda   ENTPTR
             clc
             adc   #$27             ; thirty-nine bytes on
             sta   ENTPTR
             bcc   :n2
             inc   ENTPTR+1
:n2          dec   ENTN
             bne   :entry
             jmp   :block

:shut        jsr   CLOSEF
             clc
             rts
:done        jsr   CLOSEF
             clc
             rts
:fail        sec
             rts

*--------------------------------------
* TAKEENT -- the entry at ENTPTR into the arrays, at the panel's count
*--------------------------------------
TAKEENT      ldx   PANSEL
             lda   PCOUNT,x
             jsr   NAMEAT

*--- the name, length first
             ldy   #$00
             lda   (ENTPTR),y
             and   #$0f
             sta   TMPB
             sta   (NAMPTR),y
:copy        iny
             lda   (ENTPTR),y
             sta   (NAMPTR),y
             cpy   TMPB
             bcc   :copy

*--- and the three other things a listing shows
             ldx   PANSEL
             ldy   PCOUNT,x
             lda   #$10             ; file type
             sta   TMPA
             jsr   ENTBYTE
             sta   (PTYPE),y
             lda   #$13             ; blocks used, low
             sta   TMPA
             jsr   ENTBYTE
             sta   (PBLKLO),y
             lda   #$14
             sta   TMPA
             jsr   ENTBYTE
             sta   (PBLKHI),y
             lda   #$1e             ; access; bit 1 is write-enable
             sta   TMPA
             jsr   ENTBYTE
             sta   (PACC),y
             ldx   PANSEL
             inc   PCOUNT,x
             rts

*--- A = the byte at offset TMPA of the entry, Y preserved
ENTBYTE      sty   TMPC
             ldy   TMPA
             lda   (ENTPTR),y
             ldy   TMPC
             rts

*--------------------------------------
* Building a path
*
* A path is a length byte, then the characters, low ASCII. A name is a length
* byte then the characters too -- so aiming the destination pointer one byte
* before where the name is to land lets one index walk both.
*--------------------------------------

*--- PATHVOL -- the panel's path = "/" + the name under its cursor
PATHVOL      ldx   PANSEL
             lda   PCURSEL,x
             jsr   NAMEAT
             lda   PATHPTR          ; the slash sits at path[1], so the name
             clc                    ; starts at path[2] == (PDST),1
             adc   #$01
             sta   PDST
             lda   PATHPTR+1
             adc   #$00
             sta   PDST+1
             jsr   APPNAME
             lda   TMPB
             clc
             adc   #$01             ; the name and the slash
             ldy   #$00
             sta   (PATHPTR),y
             rts

*--- PATHDOWN -- append "/" and the name under the cursor
PATHDOWN     ldx   PANSEL
             lda   PCURSEL,x
             jsr   NAMEAT
             ldy   #$00
             lda   (PATHPTR),y      ; what is already there
             sta   TMPA
             clc
             adc   PATHPTR
             sta   PDST
             lda   PATHPTR+1
             adc   #$00
             sta   PDST+1
             inc   PDST             ; the slash goes one past the end
             bne   :go
             inc   PDST+1
:go          jsr   APPNAME
             lda   TMPA
             sec                    ; the old length, the name, and the slash
             adc   TMPB
             ldy   #$00
             sta   (PATHPTR),y
             rts

*--- APPNAME -- "/" at (PDST),0 and the name from NAMPTR after it. TMPB = the
*    name length on return.
APPNAME      ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB
             lda   #$2f             ; '/', low ASCII: a path is not screen
             sta   (PDST),y
:copy        iny
             lda   (NAMPTR),y
             sta   (PDST),y
             cpy   TMPB
             bcc   :copy
             rts

*--------------------------------------
* PATHUP -- drop the last component of the panel's path
*
* Carry set if there was nothing left to drop, which means the path was a
* volume root: above that is the list of volumes, and the caller goes there.
*--------------------------------------
PATHUP       ldy   #$00
             lda   (PATHPTR),y
             beq   :top
             tay
:scan        lda   (PATHPTR),y
             cmp   #$2f             ; '/'
             beq   :found
             dey
             bne   :scan
:top         sec
             rts
:found       cpy   #$01
             beq   :top             ; "/VOLUME" -- above it is the volume list
             dey
             tya
             ldy   #$00
             sta   (PATHPTR),y
             clc
             rts

*--------------------------------------
* Per-panel state. The arrays themselves are at PAN0 and PAN1.
*--------------------------------------
             dum   $1480
PANSEL       ds    1                ; the panel SELPANEL last chose
PCOUNT       ds    2                ; entries read, per panel
PCURSEL      ds    2                ; where each cursor is
PTOP         ds    2                ; first entry visible in each
PINVOL       ds    2                ; non-zero while showing the volume list
IDX          ds    1
ENTN         ds    1
NTAG         ds    1                ; TAGSTATS: how many are tagged
TBLKLO       ds    1                ; and the blocks they come to
TBLKHI       ds    1
TGTI         ds    1                ; the target a command is working on
SCANI        ds    1                ; how far the walk has got
DIRLEN       ds    1                ; PATHBLD: the directory part's length
             dend

*--- What is being typed, and the path built from it. PROMPT has the same
*    shape as a cached name -- a length byte then the characters -- so the
*    same path builder takes either.
             dum   $1700
PROMPT       ds    16
PATHNEW      ds    65
             dend

             dum   $1500
PATH0        ds    65               ; length byte then up to 64 characters
PATH1        ds    65
             dend

*--------------------------------------
* Tags
*
* One bit an entry. A command acts on the tagged set if there is one and on
* the cursor line if there is not, which is what stops tagging being a mode
* -- see design.md section 6.
*--------------------------------------

*--- TAGBIT -- A = entry. Y = which byte of the map, TMPB = which bit.
TAGBIT       pha
             lsr
             lsr
             lsr
             tay
             pla
             and   #$07
             tax
             lda   BITS,x
             sta   TMPB
             rts

BITS         dfb   $01,$02,$04,$08,$10,$20,$40,$80

*--- TAGTOG -- turn entry A's tag over
TAGTOG       jsr   TAGBIT
             lda   (PTAGS),y
             eor   TMPB
             sta   (PTAGS),y
             rts

*--- TAGTST -- Z clear if entry A is tagged
TAGTST       jsr   TAGBIT
             lda   (PTAGS),y
             and   TMPB
             rts

*--- TAGNONE -- clear every tag in the chosen panel. Tags belong to a listing,
*    so they go when the listing does.
TAGNONE      lda   #$00
             ldy   #31
:loop        sta   (PTAGS),y
             dey
             bpl   :loop
             rts

*--------------------------------------
* TAGSTATS -- NTAG = how many are tagged, TBLK = the blocks they add up to
*
* The blocks matter more than the count: it is the number worth knowing
* before a copy.
*--------------------------------------
TAGSTATS     lda   #$00
             sta   NTAG
             sta   TBLKLO
             sta   TBLKHI
             sta   IDX
             ldx   PANSEL
:each        lda   IDX
             cmp   PCOUNT,x
             bcs   :done
             jsr   TAGTST
             beq   :next
             inc   NTAG
             ldy   IDX
             lda   TBLKLO
             clc
             adc   (PBLKLO),y
             sta   TBLKLO
             lda   TBLKHI
             adc   (PBLKHI),y
             sta   TBLKHI
:next        inc   IDX
             ldx   PANSEL
             jmp   :each
:done        rts

*--------------------------------------
* PATHBLD -- (PBUF) = the panel's directory, a slash, and the name at NAMPTR
*
* A command has to name a file to ProDOS and the panel only holds the
* directory it is in. The result goes in a buffer of the caller's choosing,
* so the panel's own path is never disturbed by an operation on one of its
* entries -- and so a rename can build the old and the new name side by side.
*--------------------------------------
PATHBLD      ldy   #$00
             lda   (PATHPTR),y
             sta   DIRLEN           ; NAMEAT uses TMPA, so this needs its own
             sta   (PBUF),y
             tay
             beq   :name
:copy        lda   (PATHPTR),y
             sta   (PBUF),y
             dey
             bne   :copy

:name        lda   PBUF
             clc
             adc   DIRLEN
             sta   PDST
             lda   PBUF+1
             adc   #$00
             sta   PDST+1
             inc   PDST             ; the slash goes one past the end
             bne   :go
             inc   PDST+1
:go          jsr   APPNAME
             lda   DIRLEN
             sec                    ; the directory, the name and the slash
             adc   TMPB
             ldy   #$00
             sta   (PBUF),y
             rts

*--------------------------------------
* PATHENT -- PATHWORK = the full path of entry A in the chosen panel
*--------------------------------------
PATHENT      jsr   NAMEAT
             lda   #<PATHWORK
             sta   PBUF
             lda   #>PATHWORK
             sta   PBUF+1
             jmp   PATHBLD

*--------------------------------------
* PATHPROMPT -- PATHNEW = the same directory with the typed name on the end
*--------------------------------------
PATHPROMPT   lda   #<PROMPT
             sta   NAMPTR
             lda   #>PROMPT
             sta   NAMPTR+1
             lda   #<PATHNEW
             sta   PBUF
             lda   #>PATHNEW
             sta   PBUF+1
             jmp   PATHBLD

*--------------------------------------
* NORMNAME -- PROMPT to what ProDOS wants: low ASCII, upper case
*
* It is typed in whatever case the keyboard was in and drawn high, and a
* pathname is the one place on this machine where the high bit stays off.
*--------------------------------------
NORMNAME     ldy   PROMPT
             beq   :done
:loop        lda   PROMPT,y
             and   #$7f
             cmp   #$61             ; 'a'
             bcc   :put
             cmp   #$7b             ; past 'z'
             bcs   :put
             sec
             sbc   #$20
:put         sta   PROMPT,y
             dey
             bne   :loop
:done        rts

*--------------------------------------
* OKNAME -- is PROMPT a name ProDOS will take? Carry set if not.
*
* One to fifteen characters, a letter first, then letters, digits and full
* stops. Checked here rather than left to the MLI, so the writer is told
* which rule they broke instead of a hex error code.
*--------------------------------------
OKNAME       lda   PROMPT
             beq   :no              ; nothing typed
             cmp   #$10
             bcs   :no              ; longer than fifteen
             lda   PROMPT+1
             jsr   ISALPHA
             bcs   :no              ; must start with a letter
             ldy   PROMPT
:loop        lda   PROMPT,y
             jsr   ISALPHA
             bcc   :next
             jsr   ISDIGIT
             bcc   :next
             cmp   #$ae             ; '.', drawn high
             bne   :no
:next        dey
             bne   :loop
             clc
             rts
:no          sec
             rts

*--- carry clear if A is a letter, either case, high ASCII
ISALPHA      cmp   #$c1             ; 'A'
             bcc   :no
             cmp   #$db             ; past 'Z'
             bcc   :yes
             cmp   #$e1             ; 'a'
             bcc   :no
             cmp   #$fb             ; past 'z'
             bcs   :no
:yes         clc
             rts
:no          sec
             rts

*--- carry clear if A is a digit
ISDIGIT      cmp   #$b0
             bcc   :no
             cmp   #$ba
             bcs   :no
             clc
             rts
:no          sec
             rts

*--------------------------------------
* Which entries a command applies to
*
* The tagged set if there is one, and the cursor line if there is not. Every
* destructive command walks its targets through here, so the rule is written
* once -- design.md section 6.
*--------------------------------------
TGTINIT      jsr   TAGSTATS         ; NTAG decides which kind of walk this is
             lda   #$00
             sta   SCANI
             rts

*--- TGTNEXT -- carry clear and TGTI = the next target; carry set at the end
TGTNEXT      lda   NTAG
             beq   :cursor

             ldx   PANSEL
:scan        lda   SCANI
             cmp   PCOUNT,x
             bcs   :none
             jsr   TAGTST
             bne   :hit
             inc   SCANI
             ldx   PANSEL
             jmp   :scan
:hit         lda   SCANI
             sta   TGTI
             inc   SCANI
             clc
             rts

:cursor      lda   SCANI
             bne   :none            ; the cursor line, and only once
             ldx   PANSEL
             lda   PCURSEL,x
             sta   TGTI
             inc   SCANI
             clc
             rts

:none        sec
             rts

*--------------------------------------
* CAPPEND -- add "/" and the name at NAMPTR to the path already in (PBUF)
*
* Descending a tree is appending a component; coming back up is taking one
* off. Both paths -- the source and the destination -- move together.
*--------------------------------------
CAPPEND      ldy   #$00
             lda   (PBUF),y
             sta   DIRLEN
             clc
             adc   PBUF
             sta   PDST
             lda   PBUF+1
             adc   #$00
             sta   PDST+1
             inc   PDST             ; the slash goes one past the end
             bne   :go
             inc   PDST+1
:go          jsr   APPNAME
             lda   DIRLEN
             sec                    ; what was there, the name, and the slash
             adc   TMPB
             ldy   #$00
             sta   (PBUF),y
             rts

*--------------------------------------
* CTRIM -- take the last component off the path in (PBUF)
*--------------------------------------
CTRIM        ldy   #$00
             lda   (PBUF),y
             beq   :done
             tay
:scan        lda   (PBUF),y
             cmp   #$2f             ; '/'
             beq   :cut
             dey
             bne   :scan
             rts
:cut         dey
             tya
             ldy   #$00
             sta   (PBUF),y
:done        rts

*--------------------------------------
* SETPW / SETPN -- aim PBUF at the source path or the destination path
*--------------------------------------
SETPW        lda   #<PATHWORK
             sta   PBUF
             lda   #>PATHWORK
             sta   PBUF+1
             rts

SETPN        lda   #<PATHNEW
             sta   PBUF
             lda   #>PATHNEW
             sta   PBUF+1
             rts
