# m-ex code modules for Rooms.
#
# Built in the same devkitPro image as the codeset:
#   docker run --rm -v $PWD:/work -w /work/Rooms/Modules \
#       nikhilnarayana/devkitpro-slippi:latest make
#
# Melee owns r13 and r2, so -msdata=none -G0 is not optional: anything the
# compiler put in .sdata would be addressed off the game's own SDA base at
# runtime. module.ld refuses to link if that happens.
#
# ⚠️ -Os, not -O2, and that is not a preference. A module is loaded onto
# the ROOM SCENE's heap, which it shares with the VS splash's own fighter
# models, and there is not much room left on it. A module that does not fit
# does not fail to load with a message - the game jumps into unmapped memory
# the instant the scene loads, and the log stops dead after "Writing file
# contents" with nothing from the module at all. See MODULE_MAX below.

# The devkitPro image sets DEVKITPPC but leaves its bin off PATH.
DEVKITPPC ?= /opt/devkitpro/devkitPPC
CC      := $(DEVKITPPC)/bin/powerpc-eabi-gcc
LD      := $(DEVKITPPC)/bin/powerpc-eabi-ld
PYTHON  := python3

CFLAGS  := -Os -mcpu=750 -meabi -mhard-float \
           -msdata=none -G0 -fno-common \
           -ffreestanding -fno-builtin -fno-asynchronous-unwind-tables \
           -fno-strict-aliasing -std=gnu11 \
           -Wall -Wextra -Werror -Iinclude

LDFLAGS := --emit-relocs -T module.ld -T melee_symbols.ld -T slippi_symbols.ld

OUT     := out
SCRIPTS := module.ld melee_symbols.ld slippi_symbols.ld

# Per module: the shipped filename - it has to match what mxscn.py wrote into
# MxScn.dat, case included - and the exports in scene-table slot order,
# 0 = Think, 1 = Load, 2 = Leave. mexpack.py looks the symbols up by name.
#
# Leave is deliberately absent. m-ex only overwrites a slot a module actually
# exports, so the scene entry keeps whatever it was built with - which is the
# whole point of copying the splash's entry rather than starting from zero.
room_DAT     := SlippiRoom.dat
room_EXPORTS := 0=room_think 1=room_load

MODULES := room

# The largest module that has been SEEN to load.
#
# ⚠️ MEASURED, not looked up. 24724 bytes is the biggest that ever ran;
# 28500 and 28628 both crashed on scene load with nothing logged. The real
# ceiling is somewhere between the two and depends on what else is on the
# scene heap that day, so this is the high-water mark rather than a limit the
# game states anywhere.
#
# ⚠️ If a build fails on this, DO NOT just raise the number. Make the
# module smaller, or find out what the heap actually has room for.
MODULE_MAX := 24724

all: include/slippi_consts.h $(foreach m,$(MODULES),$(OUT)/$($(m)_DAT))

# The MSRB offsets a module reads are the codeset's own .set values. They are
# generated rather than copied, and generated *here* rather than checked in and
# trusted: a field added to Online.s and not regenerated compiles perfectly
# against the stale header and reads the wrong bytes at runtime.
CONST_SRC := ../../Online/Online.s ../../Common/Common.s
include/slippi_consts.h: gen_slippi_consts.py $(CONST_SRC)
	$(PYTHON) gen_slippi_consts.py $(CONST_SRC) $@

define MODULE_RULE
$$(OUT)/$$($(1)_DAT): $$(wildcard $(1)/*.c) $$(wildcard include/*.h) include/slippi_consts.h $$(SCRIPTS) mexpack.py | $$(OUT)
	@mkdir -p $$(OUT)/$(1)
	$$(foreach src,$$(wildcard $(1)/*.c),\
	    $$(CC) $$(CFLAGS) -c $$(src) -o $$(OUT)/$(1)/$$(notdir $$(src:.c=.o)) &&) true
	$$(LD) $$(LDFLAGS) -o $$(OUT)/$(1).elf $$(OUT)/$(1)/*.o
	$$(PYTHON) mexpack.py $$(OUT)/$(1).elf $$@ $$($(1)_EXPORTS)
	@sz=$$$$(stat -c%s $$@); \
	 if [ $$$$sz -gt $$(MODULE_MAX) ]; then \
	   echo "$$@ is $$$$sz bytes, over the $$(MODULE_MAX) that fits on the scene heap" >&2; \
	   echo "A module that does not fit CRASHES on scene load with nothing in the log." >&2; \
	   rm -f $$@; exit 1; \
	 fi; \
	 echo "$$@ $$$$sz bytes (ceiling $$(MODULE_MAX))"
endef

$(foreach m,$(MODULES),$(eval $(call MODULE_RULE,$(m))))

$(OUT):
	mkdir -p $(OUT)

clean:
	rm -rf $(OUT)

.PHONY: all clean
