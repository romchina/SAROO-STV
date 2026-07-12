AS      := sh-elf-as
LD      := sh-elf-ld
OBJCOPY := sh-elf-objcopy

ASFLAGS := --big --isa=sh2
LDFLAGS := -T ldscript

all: stv-native-hle.bin

reloc_veneers.o: reloc_veneers.s
	$(AS) $(ASFLAGS) -o $@ $<

stv-native-hle.elf: reloc_veneers.o ldscript
	$(LD) $(LDFLAGS) $< -o $@

stv-native-hle.bin: stv-native-hle.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Size: $$(stat -c%s $@) bytes"

test-build: stv-native-hle.bin
	python3 verify_build.py stv-native-hle.elf
	sh-elf-objdump -d stv-native-hle.elf

clean:
	rm -f reloc_veneers.o stv-native-hle.elf stv-native-hle.bin

.PHONY: all test-build clean
