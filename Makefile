# a2-filer -- a two-panel ProDOS 8 file manager for the Enhanced Apple //e
#
#   make          assemble SRC with Merlin32
#   make disk     build a bootable ProDOS 8 image
#   make run      build, boot it in Virtual ][, print the screen
#   make screen   print what's on the emulated screen right now
#   make test     run the regression suite
#   make eject    flush the mounted image to disk
#   make clean

VERSION := 0.1
SRC     ?= src/filer.S
NAME    ?= ZIPFILER.SYSTEM
BUILD   := build
TOOLS   := tools

MERLIN  := $(TOOLS)/merlin32
ASMINC  := $(TOOLS)/asminc
AC      := $(TOOLS)/ac
VII     := $(TOOLS)/vii.sh

BIN     := $(BUILD)/$(NAME)
IMAGE   := $(BUILD)/ZIPFILER.po
# The replacement quit routine, and the patcher that carries it on the Apple.
# Defined here rather than beside their rules: make expands a prerequisite
# when it reads the rule, so a name defined later expands to nothing and the
# file silently never gets built.
QUITBIN := src/ZFQUIT.BIN
QPATCH  := $(BUILD)/QPATCH.SYSTEM

.PHONY: quitcode qpatch quitpatch unquit quitstatus all disk run screen test fixture card eject clean

all: $(BIN)

# Every source file, not just $(SRC): the rest are pulled in with Merlin's put
# directive, and depending on $(SRC) alone means edits to them never rebuild.
SOURCES := $(wildcard src/*.S)

# Merlin32 writes its object next to the source, named by the `dsk` directive.
# A dum block declares addresses without emitting anything, so two of them can
# quietly claim the same bytes and Merlin will not say a word.
$(BIN): $(SOURCES) | $(BUILD)
	@python3 $(TOOLS)/dumcheck.py
	@python3 $(TOOLS)/stubcheck.py
	@$(MERLIN) $(ASMINC) $(SRC) > $(BUILD)/merlin32.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/merlin32.log; exit 1; }
	@grep -iE '^\s+(Error|Warning)' $(BUILD)/merlin32.log && exit 1 || true
	@mv $(dir $(SRC))$(NAME) $(BIN)
	@rm -f $(dir $(SRC))_FileInformation.txt $(dir $(SRC))$(NAME)_Output.txt
	@echo "assembled $(SRC) -> $(BIN) ($$(stat -f%z $(BIN)) bytes)"

$(BUILD):
	@mkdir -p $(BUILD)

disk: $(IMAGE)

$(IMAGE): $(BIN) $(QPATCH)
	@VOL=ZIPFILER SYS=$(NAME) $(TOOLS)/mkdisk.sh $(IMAGE) $(BIN)
	@$(AC) -p $(IMAGE) QPATCH.SYSTEM SYS 0x2000 < $(QPATCH)

run: $(IMAGE)
	@$(VII) boot $(IMAGE)
	@$(VII) settle 6
	@echo "--- screen ---"
	@$(VII) screen

screen:
	@$(VII) screen

# The fixture is rebuilt every run: the suite writes to it, and it must never
# be anybody's real disk. See docs/design.md section 12.
test: $(IMAGE) quitcode
	@tests/mkfixture.sh >/dev/null
	@tests/run.sh "$(SECTION)"

# A disk with something on it to practise on: two levels of subdirectory and
# a few file types. build/ZIPFILER.po is bare -- just the program and ProDOS.
fixture: $(IMAGE)
	@tests/mkfixture.sh

# Copy an image to a card. VOL is the mounted volume name, e.g.
#   make card VOL="NO NAME"            the bare program disk
#   make card VOL="NO NAME" IMG=build/FIXTURE.po   with files to play with
IMG ?= $(IMAGE)
card: $(IMAGE)
	@$(TOOLS)/tocard.sh "$(VOL)" $(IMG)

# Virtual ][ buffers image writes until eject.
# --- the quit routine ------------------------------------------------------
# MLI QUIT copies four pages out of the language card to $1000 and jumps there,
# so those 1024 bytes ARE what happens when any program quits. Replacing them
# makes quitting land in ZipFiler instead of Bitsy Bye. See docs/design.md 15.
#
# It patches an IMAGE, never a mounted card and never a live boot volume, and
# it saves what it replaced so `unquit` can put it back.

# QPATCH.SYSTEM does the same job ON THE APPLE, for a volume that is not a .po
# on the Mac -- a big card partition, or one reached over a network share.
# Those are the volumes most worth having ZipFiler come back on, and there is
# no other way to reach them.

quitcode: $(QUITBIN)
qpatch: $(QPATCH)

$(QPATCH): src/qpatch.S src/zfquitdata.S | $(BUILD)
	@$(MERLIN) $(ASMINC) src/qpatch.S > $(BUILD)/qpatch.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/qpatch.log; exit 1; }
	@mv src/QPATCH.SYSTEM $(QPATCH)
	@rm -f src/_FileInformation.txt src/QPATCH.SYSTEM_Output.txt
	@echo "on-Apple patcher: $(QPATCH) ($$(stat -f%z $(QPATCH)) bytes)"

# The routine has to be carried inside QPATCH, since on the Apple there is no
# Mac to hand it over. Merlin cannot include a binary, so it becomes dfb lines.
src/zfquitdata.S: $(QUITBIN) $(TOOLS)/binblob.py
	@python3 $(TOOLS)/binblob.py $(QUITBIN) QUITCODE 1024 > $@

$(QUITBIN): src/zfquit.S
	@$(MERLIN) $(ASMINC) src/zfquit.S > $(BUILD)/zfquit.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/zfquit.log; exit 1; }
	@rm -f src/_FileInformation.txt src/ZFQUIT.BIN_Output.txt
	@echo "quit routine: $(QUITBIN) ($$(stat -f%z $(QUITBIN)) of 1024 bytes)"

quitpatch: quitcode $(IMAGE)
	@python3 $(TOOLS)/quitpatch.py install $(IMG)

unquit:
	@python3 $(TOOLS)/quitpatch.py restore $(IMG)

quitstatus:
	@python3 $(TOOLS)/quitpatch.py status $(IMG)

eject:
	@osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' 2>/dev/null || true
	@echo "ejected"

clean:
	@rm -rf $(BUILD)
	@echo "cleaned"
