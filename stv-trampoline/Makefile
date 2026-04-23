# SAROO-STV Phase 1 trampoline build.
#
# Uses binutils-sh-elf only (no C compiler needed). Assembles and links
# trampoline.s into a raw binary dropped at CS0 (0x02000000).

AS      := sh-elf-as
LD      := sh-elf-ld
OBJCOPY := sh-elf-objcopy

ASFLAGS := --big --isa=sh2
LDFLAGS := -T ldscript

OBJ := trampoline.o

all: trampoline.bin

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

trampoline.elf: $(OBJ) ldscript
	$(LD) $(LDFLAGS) $(OBJ) -o $@

trampoline.bin: trampoline.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Size: $$(stat -c%s $@) bytes"

# Predictive test: wrap as a CUE/BIN and run Mednafen.
# Mednafen actually wants a MODE1/2352 CD image. Pad with 2048-byte data
# areas and the ISO9660 / Saturn bootstrap dance. For Phase 1 smoke testing
# we just verify the ELF/BIN build succeeds; true CD image assembly comes
# with Task 7 and/or a separate mkiso step.
test-build: trampoline.bin
	@ls -l trampoline.bin trampoline.elf
	@echo
	@echo "Header dump (first 32 bytes):"
	@sh-elf-objdump -s -j .header trampoline.elf | head -10
	@echo
	@echo "Disassembly of _start:"
	@sh-elf-objdump -d -j .text trampoline.elf

clean:
	rm -f $(OBJ) trampoline.elf trampoline.bin

.PHONY: all clean test-build
