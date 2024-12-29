#------------------------------------------------------------------------------
# Z88DK Z80 Macro Assembler
#
# Copyright (C) Paulo Custodio, 2011-2024
# License: The Artistic License 2.0, http://www.perlfoundation.org/artistic_license_2_0
#------------------------------------------------------------------------------

all: opcodes.dat
opcodes.dat: make_opcodes.pl Opcodes.pm Makefile
	perl make_opcodes.pl opcodes.dat && dos2unix opcodes.dat 2> /dev/null

all: opcodes.txt
opcodes.txt: opcodes.dat dump_opcodes.pl Opcodes.pm Makefile
	perl dump_opcodes.pl opcodes.dat opcodes.txt && dos2unix opcodes.txt 2> /dev/null

all: cpu_test_z80_ok.asm
cpu_test_z80_ok.asm: opcodes.dat make_cpu_test.pl Opcodes.pm Makefile
	perl make_cpu_test.pl opcodes.dat cpu_test && dos2unix cpu_test_*.asm 2> /dev/null

all: cpu_rules.h
cpu_rules.h: opcodes.dat make_cpu_rules.pl Opcodes.pm Makefile
	perl make_cpu_rules.pl opcodes.dat cpu_rules.h && dos2unix cpu_rules.h 2> /dev/null
