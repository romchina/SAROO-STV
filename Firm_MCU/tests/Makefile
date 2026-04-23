# Host-side unit tests for Firm_MCU/Saturn/stv_rom.c.
#
# We compile the unit under test directly with -DUNIT_TEST so the platform
# shims inside the .c fall back to the host mocks. No STM32 toolchain
# required — any gcc works.

CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wno-unused-function -g -O0 -DUNIT_TEST \
           -I../Saturn

TESTS = test_stv_rom

.PHONY: all test clean

all: $(TESTS)

test: $(TESTS)
	@for t in $(TESTS); do                                       \
	    echo "--- running $$t ---";                              \
	    ./$$t || exit 1;                                         \
	done
	@echo "ALL TESTS PASS"

test_stv_rom: test_stv_rom.c ../Saturn/stv_rom.c ../Saturn/stv_rom.h
	$(CC) $(CFLAGS) test_stv_rom.c -o $@

clean:
	rm -f $(TESTS)
