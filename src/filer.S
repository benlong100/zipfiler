*--------------------------------------
* FILER.S -- a two-panel file manager for the Enhanced Apple //e
*
* ProDOS 8 enters a SYS file at $2000. See docs/design.md.
*
* At the moment one panel works and it is read-only: the list of online
* volumes, a directory read from any of them, arrow keys to move and RET to
* go in. The second panel, tagging and everything destructive are still to
* come.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   FILER.SYSTEM

*--- equates emit nothing, so they are safe here. The rest emit CODE, and
*    ProDOS enters a SYS file at $2000 -- so they are PUT at the end, after
*    the entry point, or the machine jumps straight into the display layer.
             put   equates

*--------------------------------------
* START -- both panels open on the list of volumes
*--------------------------------------
START        jsr   DISPINIT
             lda   #$00
             sta   PANEL
             lda   #$01
             jsr   SELPANEL
             jsr   TOVOLUMES
             lda   #$00
             jsr   SELPANEL
             jsr   TOVOLUMES

MAINLOOP     jsr   DRAWSCREEN
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             lda   #$00             ; a keystroke retires the last message
             sta   MSGON
             jsr   FOCUS            ; every command acts on the focused panel
             lda   KEYCHR
             cmp   #$8b             ; up arrow
             beq   :tup
             cmp   #$8a             ; down arrow
             beq   :tdown
             cmp   #$8d             ; RET: go in
             beq   :tenter
             cmp   #$88             ; left arrow: up a level
             beq   :tparent
             cmp   #$89             ; TAB: the other panel
             beq   :ttab
             cmp   #$d3             ; S, either case: swap the panels
             beq   :tswap
             cmp   #$f3
             beq   :tswap
             cmp   #$a0             ; SPACE: tag, and step down
             beq   :ttag
             cmp   #$cc             ; L, either case: lock or unlock
             beq   :tlock
             cmp   #$d2             ; R, either case: rename
             beq   :tren
             cmp   #$c4             ; D, either case: delete
             beq   :tdel
             cmp   #$c3             ; C, either case: copy, left to right
             beq   :tcpy
             cmp   #$e3
             beq   :tcpy
             cmp   #$e4
             beq   :tdel
             cmp   #$f2
             beq   :tren
             cmp   #$ec
             beq   :tlock
             cmp   #$9b             ; ESC: back to ProDOS
             beq   :tquit
             jmp   :key

*--- the handlers are further off than a branch reaches
:tup         jmp   :up
:tdown       jmp   :down
:tenter      jmp   :enter
:tparent     jmp   :parent
:ttab        jmp   :tab
:tswap       jmp   :swap
:tquit       jmp   :quit
:ttag        jmp   :tag
:tlock       jmp   :lock
:tren        jmp   :rename
:tdel        jmp   :delete
:tcpy        jmp   :copy

:tab         lda   PANEL
             eor   #$01
             sta   PANEL
             jmp   MAINLOOP

:up          ldx   PANSEL
             lda   PCURSEL,x
             bne   *+5              ; already at the top
             jmp   :key
             dec   PCURSEL,x
             lda   PCURSEL,x
             cmp   PTOP,x
             bcc   *+5
             jmp   MAINLOOP
             dec   PTOP,x
             jmp   MAINLOOP

:down        ldx   PANSEL
             lda   PCURSEL,x
             clc
             adc   #$01
             cmp   PCOUNT,x
             bcc   *+5              ; already at the end
             jmp   :key
             sta   PCURSEL,x
             sec
             sbc   PTOP,x
             cmp   #PANELROWS
             bcs   *+5
             jmp   MAINLOOP
             inc   PTOP,x
             jmp   MAINLOOP

:quit        jsr   MLI
             dfb   $65
             da    QUITPARM
             rts                    ; the MLI quit does not come back

*--- RET. From the volume list that means entering a volume; from a directory
*    it means entering a subdirectory, and nothing at all on a file.
:enter       ldx   PANSEL
             lda   PCOUNT,x
             bne   *+5
             jmp   :key
             lda   PINVOL,x
             beq   :subdir
             jsr   PATHVOL
             jmp   :read
:subdir      ldy   PCURSEL,x
             lda   (PTYPE),y
             cmp   #$0f             ; a directory, and only a directory
             beq   *+5
             jmp   :key
             jsr   PATHDOWN
:read        jsr   DIRSCAN
             bcs   :fell
             ldx   PANSEL
             lda   #$00
             sta   PINVOL,x
             sta   PCURSEL,x
             sta   PTOP,x
             jmp   MAINLOOP
:fell        jsr   TOVOLUMES        ; unreadable: fall back to the list
             jmp   MAINLOOP

*--- Left arrow. Up out of a directory, and up out of a volume root is the
*    list of volumes -- which is what makes the volume picker not a command.
:parent      ldx   PANSEL
             lda   PINVOL,x
             beq   *+5              ; already as far out as there is
             jmp   :key
             jsr   PATHUP
             bcs   :fell
             jsr   DIRSCAN
             bcs   :fell
             ldx   PANSEL
             lda   #$00
             sta   PCURSEL,x
             sta   PTOP,x
             jmp   MAINLOOP

*--- S. Exchange the two panels, which is how anything is copied right to
*    left: the direction of a copy is fixed, so the panels move instead.
:swap        ldy   #$00
:sw          lda   PATH0,y
             tax
             lda   PATH1,y
             sta   PATH0,y
             txa
             sta   PATH1,y
             iny
             cpy   #65
             bcc   :sw
             lda   PINVOL
             ldx   PINVOL+1
             sta   PINVOL+1
             stx   PINVOL
             lda   #$00
             jsr   SELPANEL
             jsr   RESCAN
             lda   #$01
             jsr   SELPANEL
             jsr   RESCAN
             lda   #$00
             sta   PCURSEL
             sta   PCURSEL+1
             sta   PTOP
             sta   PTOP+1
             jmp   MAINLOOP

*--- SPACE tags the entry and steps down, so tagging a run is tapping the
*    space bar. At the end of the listing it tags and stays put.
:tag         ldx   PANSEL
             lda   PCOUNT,x
             bne   *+5
             jmp   :key
             lda   PCURSEL,x
             jsr   TAGTOG
             ldx   PANSEL
             lda   PCURSEL,x
             clc
             adc   #$01
             cmp   PCOUNT,x
             bcs   :tagged
             sta   PCURSEL,x
             sec
             sbc   PTOP,x
             cmp   #PANELROWS
             bcc   :tagged
             inc   PTOP,x
:tagged      jmp   MAINLOOP

*--- L. Lock, unless everything it applies to is locked already, in which case
*    unlock: one key, and it does the thing that is not already true.
:lock        ldx   PANSEL
             lda   PINVOL,x
             beq   *+5
             jmp   :novol           ; a volume has no access byte to change
             ldx   PANSEL
             lda   PCOUNT,x
             bne   *+5
             jmp   :key
             jsr   LOCKCMD
             jmp   MAINLOOP
:novol       lda   #<MVOL
             ldy   #>MVOL
             jsr   SAYTEXT
             jmp   MAINLOOP

*--- R. Rename takes the cursor line and ignores tags: renaming five files to
*    one name means nothing -- design.md section 6.
:rename      ldx   PANSEL
             lda   PINVOL,x
             beq   *+5
             jmp   :renvol          ; a volume is renamed by another route
             ldx   PANSEL
             lda   PCOUNT,x
             bne   *+5
             jmp   :key
             jsr   RENCMD
             jmp   MAINLOOP
:renvol      lda   #<MRENVOL
             ldy   #>MRENVOL
             jsr   SAYTEXT
             jmp   MAINLOOP

*--- D. The one command with nothing behind it, so it asks first.
:delete      ldx   PANSEL
             lda   PINVOL,x
             beq   *+5
             jmp   :delvol          ; a volume is not deleted from a listing
             ldx   PANSEL
             lda   PCOUNT,x
             bne   *+5
             jmp   :key
             jsr   DELCMD
             jmp   MAINLOOP
:delvol      lda   #<MDELVOL
             ldy   #>MDELVOL
             jsr   SAYTEXT
             jmp   MAINLOOP

*--- C. Always left to right, so the direction never has to be said.
:copy        lda   PINVOL           ; the left panel, which is where a copy
             beq   *+5              ; comes from
             jmp   :cpyvol
             lda   PCOUNT
             bne   *+5
             jmp   :key
             lda   PINVOL+1         ; and the right, which is where it goes
             beq   *+5
             jmp   :cpyvol
             jsr   CPYCMD
             jmp   MAINLOOP
:cpyvol      lda   #<MCPYVOL
             ldy   #>MCPYVOL
             jsr   SAYTEXT
             jmp   MAINLOOP

QUITPARM     dfb   $04
             dfb   $00
             da    $0000
             dfb   $00
             da    $0000

*--------------------------------------
* TOVOLUMES -- the chosen panel shows the list of online volumes
*--------------------------------------
TOVOLUMES    jsr   VOLSCAN
             ldx   PANSEL
             lda   #$01
             sta   PINVOL,x
             lda   #$00
             sta   PCURSEL,x
             sta   PTOP,x
             rts

*--------------------------------------
* FOCUS -- point the working pointers at the panel that has focus
*--------------------------------------
FOCUS        lda   PANEL
             jmp   SELPANEL

*--------------------------------------
* RESCAN -- read the chosen panel again, whichever listing it is showing
*--------------------------------------
RESCAN       ldx   PANSEL
             lda   PINVOL,x
             beq   :dir
             jmp   VOLSCAN
:dir         jmp   DIRSCAN

*--------------------------------------
* LOCKCMD -- lock or unlock everything the command applies to
*
* Two passes. The first asks whether they are ALL locked already, because
* that is what decides which way one key should go. The second does it.
*
* The access byte is changed rather than replaced: the destroy, rename and
* write bits go off or on and everything else in it -- the backup bit above
* all -- is left exactly as ProDOS had it.
*--------------------------------------
LOCKCMD      jsr   TGTINIT
             lda   #$01
             sta   ALLLOCK
:ask         jsr   TGTNEXT
             bcs   :apply
             ldy   TGTI
             lda   (PACC),y
             and   #$02             ; write-enable: set means unlocked
             beq   :ask
             lda   #$00
             sta   ALLLOCK
             jmp   :ask

:apply       jsr   TGTINIT
             lda   #$00
             sta   NDONE
             sta   NSKIP
:each        jsr   TGTNEXT
             bcs   :done
             lda   TGTI
             jsr   PATHENT
             jsr   GINFOF
             bcs   :skip

             lda   GACCESS
             ldx   ALLLOCK
             bne   :unlock
             and   #$3d             ; clear destroy, rename and write
             jmp   :put
:unlock      ora   #$c2             ; and set them again
:put         sta   SACCESS

*--- the fields SET_FILE_INFO carries over, copied deliberately. Its reserved
*    bytes are where GET_FILE_INFO left the storage type and block count, so
*    the two blocks are never shared.
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
             jsr   SINFOF
             bcs   :skip
             inc   NDONE
             jmp   :each
:skip        inc   NSKIP
             jmp   :each

:done        jsr   RESCAN           ; the listing has changed underneath us
             lda   NDONE
             sta   MSGN
             lda   ALLLOCK
             bne   :sayun
             lda   #<MLOCKED
             ldy   #>MLOCKED
             jmp   SAYMSG
:sayun       lda   #<MUNLOCK
             ldy   #>MUNLOCK
             jmp   SAYMSG

*--------------------------------------
* RENCMD -- rename the entry under the cursor
*--------------------------------------
RENCMD       ldx   PANSEL
             lda   PCURSEL,x
             pha
             jsr   PATHENT          ; what it is called now

*--- the prompt starts out holding the existing name, so a small change is a
*    small amount of typing
             pla
             jsr   NAMEAT
             ldy   #$00
             lda   (NAMPTR),y
             sta   PROMPT
             sta   TMPB
             beq   :ask
:fill        iny
             lda   (NAMPTR),y
             ora   #$80             ; held low, typed and drawn high
             sta   PROMPT,y
             cpy   TMPB
             bcc   :fill

:ask         jsr   PROMPTIN
             bcc   :check
             lda   #<MCANCEL
             ldy   #>MCANCEL
             jmp   SAYTEXT

:check       jsr   OKNAME
             bcc   :doit
             lda   #<MBADNAME
             ldy   #>MBADNAME
             jmp   SAYTEXT

:doit        jsr   NORMNAME
             jsr   PATHPROMPT
             jsr   RENAMEF
             bcs   :failed
             jsr   RESCAN
             lda   #<MRENAMED
             ldy   #>MRENAMED
             jmp   SAYTEXT
:failed      lda   MLIERR
             sta   MSGN
             lda   #<MRENERR
             ldy   #>MRENERR
             jmp   SAYMSG

*--------------------------------------
* DELCMD -- delete what the command applies to
*
* A locked file is not deleted and is not treated as a failure: the lock is
* the writer's stated intent and L is one key away. It is counted and said
* out loud instead -- design.md section 7.
*--------------------------------------
DELCMD       jsr   TGTINIT
             lda   #$00
             sta   NDONE            ; how many CAN go
             sta   NSKIP
:count       jsr   TGTNEXT
             bcs   :ask
             ldy   TGTI
             lda   (PACC),y
             and   #$02             ; write-enable: clear means locked
             bne   :countable
             inc   NSKIP
             jmp   :count
:countable   inc   NDONE
             jmp   :count

:ask         lda   NDONE
             bne   :confirm
             lda   NSKIP            ; everything it applies to is locked
             sta   MSGN
             lda   #<MALLLOCK
             ldy   #>MALLLOCK
             jmp   SAYMSG

:confirm     lda   NDONE
             sta   MSGN
             lda   #<MASKDEL
             ldy   #>MASKDEL
             jsr   CONFIRM
             bcc   :go
             lda   #<MKEPT
             ldy   #>MKEPT
             jmp   SAYTEXT

*--- and now it is irreversible
:go          jsr   TGTINIT
             lda   #$00
             sta   NDONE
             sta   NSKIP
             sta   NFAIL
:each        jsr   TGTNEXT
             bcs   :done
             ldy   TGTI
             lda   (PACC),y
             and   #$02
             beq   :locked
             lda   TGTI
             jsr   PATHENT
             jsr   DESTROYF
             bcs   :failed
             inc   NDONE
             jmp   :each
:locked      inc   NSKIP
             jmp   :each
*--- ProDOS said no. Keep the code now: the rescan below makes its own MLI
*    calls and MLIERR will be theirs by the time anyone looks.
:failed      lda   MLIERR
             sta   DELERR
             inc   NFAIL
             jmp   :each

:done        jsr   RESCAN
             jsr   CLAMPSEL

*--- A refusal by ProDOS and a file the writer locked are different things and
*    are not to be reported as though they were the same.
             lda   NFAIL
             beq   :nofail
             lda   DELERR
             cmp   #$4e             ; the one worth naming: it is not empty
             beq   :notempty
             sta   MSGN
             lda   #<MDELERR
             ldy   #>MDELERR
             jmp   SAYMSG
:notempty    lda   #<MNOTEMPTY
             ldy   #>MNOTEMPTY
             jmp   SAYTEXT

:nofail      lda   NSKIP
             beq   :plain
             lda   NDONE
             beq   :none
             sta   MSGN
             lda   #<MDELSOME
             ldy   #>MDELSOME
             jmp   SAYMSG
:none        lda   NSKIP
             sta   MSGN
             lda   #<MALLLOCK
             ldy   #>MALLLOCK
             jmp   SAYMSG
:plain       lda   NDONE
             sta   MSGN
             lda   #<MDELETED
             ldy   #>MDELETED
             jmp   SAYMSG

*--------------------------------------
* CLAMPSEL -- keep the cursor inside a listing that just got shorter
*--------------------------------------
CLAMPSEL     ldx   PANSEL
             lda   PCOUNT,x
             bne   :some
             sta   PCURSEL,x        ; an empty listing: the cursor is at zero
             sta   PTOP,x
             rts
:some        sec
             sbc   #$01
             cmp   PCURSEL,x
             bcs   :top
             sta   PCURSEL,x
:top         lda   PCURSEL,x
             cmp   PTOP,x
             bcs   :done
             sta   PTOP,x
:done        rts

*--------------------------------------
* CONFIRM -- ask before something that cannot be taken back
*   MSGN and A/Y as SAYMSG. Carry clear only for Y.
*--------------------------------------
CONFIRM      sta   MSGPTR
             sty   MSGPTR+1
             jsr   DRAWCONFIRM
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             lda   KEYCHR
             cmp   #$9b             ; ESC means no, like everywhere else
             beq   :no
             and   #$df             ; either case
             cmp   #$d9             ; Y
             beq   :yes
             cmp   #$ce             ; N
             beq   :no
             jmp   :key
:yes         clc
             rts
:no          sec
             rts

DRAWCONFIRM  jsr   CLRBUF
             lda   MSGN
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             sta   TMPA
             jsr   PUTNUM
             lda   MSGPTR
             ldy   MSGPTR+1
             jsr   SETSTR
             ldx   #$06
             jsr   BUFSTR
             jsr   INVBUF           ; a question the eye cannot miss
             lda   #STATROW
             jmp   DRAWLINE

*--------------------------------------
* PROMPTIN -- collect a name into PROMPT. Carry set if it was abandoned.
*
* The only place in the program that takes text, which is why every command
* can be a bare letter everywhere else.
*--------------------------------------
PROMPTIN     jsr   DRAWPROMPT
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             lda   KEYCHR
             cmp   #$8d             ; RET: take it
             beq   :done
             cmp   #$9b             ; ESC: abandon it
             beq   :quit
             cmp   #$88             ; left arrow, and Delete, rub out
             beq   :rub
             cmp   #$ff
             beq   :rub
             cmp   #$a0             ; anything below space is not a name
             bcc   :key
             ldx   PROMPT
             cpx   #$0f             ; fifteen is all ProDOS will hold
             bcs   :key
             inx
             sta   PROMPT,x
             stx   PROMPT
             jmp   PROMPTIN
:rub         ldx   PROMPT
             beq   :key
             dex
             stx   PROMPT
             jmp   PROMPTIN
:done        clc
             rts
:quit        sec
             rts

*--------------------------------------
* DRAWPROMPT -- the status row, holding what has been typed so far
*--------------------------------------
DRAWPROMPT   jsr   CLRBUF
             lda   #<MNEWNAME
             ldy   #>MNEWNAME
             jsr   SETSTR
             ldx   #$00
             jsr   BUFSTR
             ldx   #$0a             ; the label already ends in a space
             lda   PROMPT
             beq   :caret
             sta   TMPB
             ldy   #$01
:copy        lda   PROMPT,y
             sta   LINEBUF,x
             inx
             cpy   TMPB
             bcs   :caret
             iny
             bne   :copy
:caret       lda   #$20             ; an inverse space, so there is a cursor
             sta   LINEBUF,x
             lda   #STATROW
             jmp   DRAWLINE

*--------------------------------------
* SAYMSG -- a count and a phrase in the status row, until the next keystroke
* SAYTEXT -- a phrase on its own
*--------------------------------------
SAYMSG       sta   MSGPTR
             sty   MSGPTR+1
             lda   #$01
             sta   MSGON
             sta   MSGNUM
             rts

SAYTEXT      sta   MSGPTR
             sty   MSGPTR+1
             lda   #$01
             sta   MSGON
             lda   #$00
             sta   MSGNUM
             rts

*--------------------------------------
* DRAWSCREEN -- the whole layout
*--------------------------------------
DRAWSCREEN   jsr   DRAWPATHS
             jsr   DRAWRULE
             jsr   DRAWENTRIES
             jsr   DRAWSTATUS
             jsr   DRAWHINTS
             jmp   FOCUS            ; leave the pointers where the keys expect

*--------------------------------------
* DRAWPATHS -- where each panel is, the focused one marked
*--------------------------------------
DRAWPATHS    jsr   CLRBUF
             jsr   PANELBAR
             lda   #$00
             jsr   SELPANEL
             lda   #$00
             sta   FCOL
             lda   #LWIDTH
             sta   FWIDTH
             jsr   ONEPATH
             lda   #$01
             jsr   SELPANEL
             lda   #RCOL
             sta   FCOL
             lda   #RWIDTH
             sta   FWIDTH
             jsr   ONEPATH
             lda   #PATHROW
             jmp   DRAWLINE

ONEPATH      lda   FCOL
             clc
             adc   FWIDTH
             sta   TMPC             ; one past this panel's last column
             ldx   FCOL
             lda   PANSEL
             cmp   PANEL
             bne   :nomark
             lda   #$be             ; '>' marks the panel with focus
             sta   LINEBUF,x
:nomark      inx
             ldy   PANSEL
             lda   PINVOL,y
             beq   :path
             lda   #<VOLTXT
             ldy   #>VOLTXT
             jsr   SETSTR
             jmp   BUFSTR
:path        ldy   #$00
             lda   (PATHPTR),y
             beq   :done
             sta   TMPB
             ldy   #$01
:copy        lda   (PATHPTR),y
             ora   #$80
             sta   LINEBUF,x
             inx
             cpx   TMPC
             bcs   :done            ; clipped at this panel's edge
             cpy   TMPB
             bcs   :done
             iny
             bne   :copy
:done        rts

*--------------------------------------
* DRAWRULE -- dashes across, with the divider crossing them
*--------------------------------------
DRAWRULE     lda   #CHDASH
             ldx   #SCRWM1
:loop        sta   LINEBUF,x
             dex
             bpl   :loop
             lda   #CHPLUS
             ldx   #SEPCOL
             sta   LINEBUF,x
             lda   #RULEROW
             jmp   DRAWLINE

*--------------------------------------
* PANELBAR -- the divider in the column between the panels
*--------------------------------------
PANELBAR     lda   #CHBAR
             ldx   #SEPCOL
             sta   LINEBUF,x
             rts

*--------------------------------------
* DRAWENTRIES -- one row of both panels at a time
*--------------------------------------
DRAWENTRIES  lda   #$00
             sta   ROWN
:row         jsr   CLRBUF
             jsr   PANELBAR
             lda   #$00
             jsr   SELPANEL
             lda   #$00
             sta   FCOL
             lda   #LWIDTH
             sta   FWIDTH
             jsr   ONEENTRY
             lda   #$01
             jsr   SELPANEL
             lda   #RCOL
             sta   FCOL
             lda   #RWIDTH
             sta   FWIDTH
             jsr   ONEENTRY
             lda   ROWN
             clc
             adc   #TOPROW
             jsr   DRAWLINE
             inc   ROWN
             lda   ROWN
             cmp   #PANELROWS
             bcc   :row
             rts

ONEENTRY     ldx   PANSEL
             lda   PTOP,x
             clc
             adc   ROWN
             sta   ENTI
             cmp   PCOUNT,x
             bcs   :none            ; past the end: leave the row blank
             jsr   FMTPANEL
             lda   PANSEL           ; only the focused panel shows a cursor
             cmp   PANEL
             bne   :none
             ldx   PANSEL
             lda   ENTI
             cmp   PCURSEL,x
             bne   :none
             jsr   INVPANEL
:none        rts

*--------------------------------------
* FMTPANEL -- entry ENTI of the chosen panel into LINEBUF
*
* The columns docs/design.md counted, offset by where the panel starts:
* 0 tag, 1 lock, 2-16 name, 18-20 type, 22-26 blocks.
*--------------------------------------
FMTPANEL     lda   ENTI
             jsr   NAMEAT
             ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB
             beq   :type
             lda   FCOL
             clc
             adc   #$02
             tax
:copy        iny
             lda   (NAMPTR),y
             ora   #$80             ; held low ASCII, drawn high
             sta   LINEBUF,x
             inx
             cpy   TMPB
             bcc   :copy

:type        ldy   ENTI
             lda   (PTYPE),y
             sta   TMPC
             lda   FCOL
             clc
             adc   #$12
             tax
             lda   TMPC
             jsr   TYPESTR

*--- the tag column
             lda   ENTI
             jsr   TAGTST
             beq   :lock
             ldx   FCOL
             lda   #$be             ; '>' -- this one is tagged
             sta   LINEBUF,x

*--- locked is the access byte's write-enable bit, clear
:lock        ldy   ENTI
             lda   (PACC),y
             and   #$02
             bne   :blocks
             lda   FCOL
             clc
             adc   #$01
             tax
             lda   #$aa             ; '*', the same mark CATALOG uses
             sta   LINEBUF,x

:blocks      ldx   PANSEL
             lda   PINVOL,x
             bne   :done            ; a volume has no size in this listing
             ldy   ENTI
             lda   (PBLKLO),y
             sta   NUMLO
             lda   (PBLKHI),y
             sta   NUMHI
             lda   FCOL
             clc
             adc   #$16
             sta   TMPA
             jsr   PUTNUM
:done        rts

*--------------------------------------
* PUTNUM -- NUMLO/NUMHI right aligned in five columns from TMPA
*--------------------------------------
PUTNUM       lda   #$00
             sta   LEADZ
             ldy   #$00
:power       lda   #$00
             sta   DIG
:sub         lda   NUMLO
             sec
             sbc   POWLO,y
             tax
             lda   NUMHI
             sbc   POWHI,y
             bcc   :emit
             stx   NUMLO
             sta   NUMHI
             inc   DIG
             jmp   :sub
:emit        lda   DIG
             bne   :show
             lda   LEADZ
             bne   :show
             cpy   #$04             ; the units digit shows even as a zero
             beq   :show
             lda   #CHSPACE
             bne   :put             ; always taken
:show        lda   #$01
             sta   LEADZ
             lda   DIG
             clc
             adc   #$b0
:put         ldx   TMPA
             sta   LINEBUF,x
             inc   TMPA
             iny
             cpy   #$05
             bcc   :power
             rts

POWLO        dfb   $10,$e8,$64,$0a,$01
POWHI        dfb   $27,$03,$00,$00,$00

*--------------------------------------
* TYPESTR -- A = ProDOS file type, X = column. Three characters into LINEBUF.
*
* A table of the types worth naming, and hex for the rest, which is what a
* catalogue has always done with a type it does not recognise.
*--------------------------------------
TYPESTR      sta   TMPB
             stx   TMPA
             ldy   #$00
:scan        cpy   #TYPLEN
             bcs   :hex
             lda   TYPTBL,y
             cmp   TMPB
             beq   :found
             iny
             iny
             iny
             iny
             bne   :scan

:found       ldx   TMPA
             iny
             lda   TYPTBL,y
             sta   LINEBUF,x
             inx
             iny
             lda   TYPTBL,y
             sta   LINEBUF,x
             inx
             iny
             lda   TYPTBL,y
             sta   LINEBUF,x
             rts

:hex         ldx   TMPA
             lda   #$a4             ; '$'
             sta   LINEBUF,x
             inx
             lda   TMPB
             lsr
             lsr
             lsr
             lsr
             jsr   HEXDIG
             sta   LINEBUF,x
             inx
             lda   TMPB
             and   #$0f
             jsr   HEXDIG
             sta   LINEBUF,x
             rts

HEXDIG       cmp   #$0a
             bcc   :digit
             clc
             adc   #$b7             ; 'A' - 10
             rts
:digit       clc
             adc   #$b0             ; '0'
             rts

TYPTBL       dfb   TYPVOL
             asc   "VOL"
             dfb   $04
             asc   "TXT"
             dfb   $06
             asc   "BIN"
             dfb   $0f
             asc   "DIR"
             dfb   $19
             asc   "ADB"
             dfb   $1a
             asc   "AWP"
             dfb   $1b
             asc   "ASP"
             dfb   $fc
             asc   "BAS"
             dfb   $fd
             asc   "VAR"
             dfb   $fe
             asc   "REL"
             dfb   $ff
             asc   "SYS"
TYPLEN       equ   *-TYPTBL

*--------------------------------------
* DRAWSTATUS / DRAWHINTS
*--------------------------------------
DRAWSTATUS   jsr   CLRBUF
             jsr   PANELBAR
             lda   MSGON
             beq   :counts
             lda   MSGNUM
             beq   :textonly
             lda   MSGN
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             sta   TMPA
             jsr   PUTNUM
             lda   MSGPTR
             ldy   MSGPTR+1
             jsr   SETSTR
             ldx   #$06
             jsr   BUFSTR
             jmp   :draw
:textonly    lda   MSGPTR
             ldy   MSGPTR+1
             jsr   SETSTR
             ldx   #$00
             jsr   BUFSTR
             jmp   :draw

:counts      jsr   FOCUS            ; the focused panel is the one described
             jsr   TAGSTATS
             lda   NTAG
             beq   :plain

*--- "n tagged, m blocks". The blocks are the number worth knowing before a
*    copy, which is why they are here and not the count alone.
             lda   NTAG
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             sta   TMPA
             jsr   PUTNUM
             lda   #<TAGTXT
             ldy   #>TAGTXT
             jsr   SETSTR
             ldx   #$06
             jsr   BUFSTR
             lda   TBLKLO
             sta   NUMLO
             lda   TBLKHI
             sta   NUMHI
             lda   #$0e
             sta   TMPA
             jsr   PUTNUM
             lda   #<BLKTXT
             ldy   #>BLKTXT
             jsr   SETSTR
             ldx   #$14
             jsr   BUFSTR
             jmp   :draw

:plain       ldx   PANEL
             lda   PCOUNT,x
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             sta   TMPA
             jsr   PUTNUM
             lda   #<ENTTXT
             ldy   #>ENTTXT
             jsr   SETSTR
             ldx   #$06
             jsr   BUFSTR
:draw        lda   #STATROW
             jmp   DRAWLINE

DRAWHINTS    jsr   CLRBUF
             lda   #<HINTTXT
             ldy   #>HINTTXT
             jsr   SETSTR
             jsr   CENTRE
             jsr   BUFSTR
             jsr   INVBUF           ; the hint row is chrome, so inverse
             lda   #HINTROW
             jmp   DRAWLINE

VOLTXT       asc   "(volumes)"
             dfb   $00
ENTTXT       asc   "entries"
             dfb   $00
TAGTXT       asc   "tagged,"
             dfb   $00
BLKTXT       asc   "blocks"
             dfb   $00
MLOCKED      asc   "locked"
             dfb   $00
MUNLOCK      asc   "unlocked"
             dfb   $00
MVOL         asc   "a volume cannot be locked"
             dfb   $00
MRENVOL      asc   "a volume is not renamed from here"
             dfb   $00
MNEWNAME     asc   "NEW NAME: "
             dfb   $00
MCANCEL      asc   "left alone"
             dfb   $00
MBADNAME     asc   "a name is 1-15 characters, a letter first"
             dfb   $00
MRENAMED     asc   "renamed"
             dfb   $00
MRENERR      asc   "ProDOS would not: error"
             dfb   $00
MDELVOL      asc   "a volume is not deleted from here"
             dfb   $00
MASKDEL      asc   "to delete, and it cannot be undone.  Y or N?"
             dfb   $00
MKEPT        asc   "kept"
             dfb   $00
MDELETED     asc   "deleted"
             dfb   $00
MDELSOME     asc   "deleted; the rest were locked"
             dfb   $00
MALLLOCK     asc   "locked, and so not deleted"
             dfb   $00
MDELERR      asc   "ProDOS refused; error code"
             dfb   $00
MNOTEMPTY    asc   "a directory has to be empty first"
             dfb   $00
MCPYVOL      asc   "both panels need to be in a directory"
             dfb   $00
HINTTXT      asc   "SPC tag  RET open  C opy  L ock  R name  D el  S wap  TAB"
             dfb   $00

*--- mutable storage
             dum   $1400
ROWN         ds    1                ; which panel row is being drawn
ENTI         ds    1                ; the entry being drawn
FCOL         ds    1                ; the column that panel starts at
FWIDTH       ds    1                ; and how wide it is
PANEL        ds    1                ; which panel has focus
NUMLO        ds    1                ; PUTNUM's value
NUMHI        ds    1
DIG          ds    1
LEADZ        ds    1
ALLLOCK      ds    1                ; is every target locked already?
NDONE        ds    1                ; what a command managed
NSKIP        ds    1                ; and what it could not
NFAIL        ds    1                ; refused by ProDOS, which is not the same
DELERR       ds    1                ; and the code it refused with
MSGON        ds    1                ; a message owns the status row
MSGNUM       ds    1                ; and whether it has a count in front
MSGN         ds    1
MSGPTR       ds    2
             dend

*--- The rest emit code, and $2000 belongs to START.
             put   screen
             put   prodos
             put   catalog
             put   copy
