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
NAME    ?= FILER.SYSTEM
BUILD   := build
TOOLS   := tools

MERLIN  := $(TOOLS)/merlin32
ASMINC  := $(TOOLS)/asminc
AC      := $(TOOLS)/ac
VII     := $(TOOLS)/vii.sh

BIN     := $(BUILD)/$(NAME)
IMAGE   := $(BUILD)/FILER.po

.PHONY: all disk run screen test eject clean

all: $(BIN)

# Every source file, not just $(SRC): the rest are pulled in with Merlin's put
# directive, and depending on $(SRC) alone means edits to them never rebuild.
SOURCES := $(wildcard src/*.S)

# Merlin32 writes its object next to the source, named by the `dsk` directive.
$(BIN): $(SOURCES) | $(BUILD)
	@$(MERLIN) $(ASMINC) $(SRC) > $(BUILD)/merlin32.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/merlin32.log; exit 1; }
	@grep -iE '^\s+(Error|Warning)' $(BUILD)/merlin32.log && exit 1 || true
	@mv $(dir $(SRC))$(NAME) $(BIN)
	@rm -f $(dir $(SRC))_FileInformation.txt $(dir $(SRC))$(NAME)_Output.txt
	@echo "assembled $(SRC) -> $(BIN) ($$(stat -f%z $(BIN)) bytes)"

$(BUILD):
	@mkdir -p $(BUILD)

disk: $(IMAGE)

$(IMAGE): $(BIN)
	@VOL=FILER SYS=$(NAME) $(TOOLS)/mkdisk.sh $(IMAGE) $(BIN)

run: $(IMAGE)
	@$(VII) boot $(IMAGE)
	@$(VII) settle 6
	@echo "--- screen ---"
	@$(VII) screen

screen:
	@$(VII) screen

# The fixture is rebuilt every run: the suite writes to it, and it must never
# be anybody's real disk. See docs/design.md section 12.
test: $(IMAGE)
	@tests/mkfixture.sh >/dev/null
	@tests/run.sh $(SECTION)

# Virtual ][ buffers image writes until eject.
eject:
	@osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' 2>/dev/null || true
	@echo "ejected"

clean:
	@rm -rf $(BUILD)
	@echo "cleaned"
