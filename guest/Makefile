AS ?= /usr/riscv32-elf/bin/as
LD ?= /usr/riscv32-elf/bin/ld
STRIP ?= /usr/riscv32-elf/bin/strip

fibonacci: fibonacci.S
	$(AS) -march=rv32ima -mabi=ilp32 $< -o fibonacci.o
	$(LD) -m elf32lriscv -Ttext=0x10000 -e _start fibonacci.o -o $@
	$(STRIP) --strip-all $@

.PHONY: clean
clean:
	rm -f fibonacci fibonacci.o
