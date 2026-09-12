# m-ex code modules for Peppy.
#
# Built in the same devkitPro image as the codeset:
#   docker run --rm -v $PWD:/work -w /work/Peppy/Modules \
#       nikhilnarayana/devkitpro-slippi:latest make
#
# Melee owns r13 and r2, so -msdata=none -G0 is not optional: anything the
# compiler put in .sdata would be addressed off the game's own SDA base at
# runtime.  module.ld refuses to link if that happens.

CC      := powerpc-eabi-gcc
LD      := powerpc-eabi-ld
PYTHON  := python3

CFLAGS  := -O2 -mcpu=750 -meabi -mhard-float \
           -msdata=none -G0 -fno-common \
           -ffreestanding -fno-builtin -fno-asynchronous-unwind-tables \
           -fno-strict-aliasing -std=gnu11 \
           -Wall -Wextra -Werror -Iinclude

LDFLAGS := --emit-relocs -T module.ld -T melee_symbols.ld -T slippi_symbols.ld

OUT     := out
SCRIPTS := module.ld melee_symbols.ld slippi_symbols.ld

# Each module's exports, in scene-table slot order: 0 = Think, 1 = Load,
# 2 = Leave.  mexpack.py looks these symbols up by name in the linked ELF.
boot_EXPORTS := 0=peppy_boot_think 1=peppy_boot_load 2=peppy_boot_leave

MODULES := boot

all: $(patsubst %,$(OUT)/Peppy%.dat,$(MODULES))

define MODULE_RULE
$$(OUT)/Peppy$(1).dat: $$(wildcard $(1)/*.c) $$(wildcard include/*.h) $$(SCRIPTS) mexpack.py | $$(OUT)
	@mkdir -p $$(OUT)/$(1)
	$$(foreach src,$$(wildcard $(1)/*.c),\
	    $$(CC) $$(CFLAGS) -c $$(src) -o $$(OUT)/$(1)/$$(notdir $$(src:.c=.o)) &&) true
	$$(LD) $$(LDFLAGS) -o $$(OUT)/$(1).elf $$(OUT)/$(1)/*.o
	$$(PYTHON) mexpack.py $$(OUT)/$(1).elf $$@ $$($(1)_EXPORTS)
endef

$(foreach m,$(MODULES),$(eval $(call MODULE_RULE,$(m))))

$(OUT):
	mkdir -p $(OUT)

clean:
	rm -rf $(OUT)

.PHONY: all clean
