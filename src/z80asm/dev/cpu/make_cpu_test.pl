#!/usr/bin/env perl

#------------------------------------------------------------------------------
# Build test files for the assembler
#------------------------------------------------------------------------------

use Modern::Perl;
BEGIN { 
	use Path::Tiny;
	use lib path($0)->dirname;
	use Opcodes;
}
use List::Util qw( min max );
use Clone 'clone';
use Carp (); 
$SIG{__DIE__} = \&Carp::confess;
use warnings FATAL => 'uninitialized'; 

@ARGV==2 or die "Usage: $0 input_file.dat output_basename\n";
my($input_file, $output_basename) = @ARGV;

my $opcodes = Opcodes->from_file($input_file);

my @test;
my %all_opcodes;

# dump cpu_ok and cpu_ixiy_ok
for my $ixiy ("", "_ixiy") {
	for my $cpu (Opcode->cpus) {
		@test = ();
		
		for my $asm (sort keys %{$opcodes->opcodes}) {
			my $asm_ixiy = $asm;
			if ($ixiy) {
				$asm_ixiy =~ s/\b(ix|iy)/$1 eq 'ix' ? 'iy' : 'ix'/eg;
			}
			
			if ($opcodes->exists($asm_ixiy, $cpu)) {
				my $opcode = $opcodes->opcodes->{$asm_ixiy}{$cpu};
				add($cpu, clone($opcode));	# make a deep copy
			}
		}
		
		open(my $fh, ">", "${output_basename}_${cpu}${ixiy}_ok.asm") or die $!;
		say $fh join("\n", compute_labels($cpu, sort @test));
	}
}

# dump cpu_error
for my $cpu (Opcode->cpus) {
	@test = ();
	
	for my $asm (sort keys %{$all_opcodes{ALL}}) {
		#say "$cpu\t$asm" if $asm =~ /ld \(sp\+/;

		if (!exists $all_opcodes{$cpu}{$asm} &&
		    !exists $all_opcodes{$cpu}{$asm =~ s/0x1234[0-9A-F]+/0x1234/r} &&
			!exists $all_opcodes{$cpu}{$asm =~ s/0x1234\b/0x123456/r} &&
			!exists $all_opcodes{$cpu}{$asm =~ s/sp[+-]\d+/sp+0/r} &&
			!exists $all_opcodes{$cpu}{$asm =~ s/sp[+-]\d+/sp-128/r} ) {
			my $skip = 0;

			# special case: 'djnz ASMPC' is translated to 'djnz NN' in 8080/8085
			if ($asm =~ /^(jr|djnz)/) {
				if ($cpu =~ /^80/) {
					$skip = 1 if $asm =~ /ASMPC/;	# DIS
				}
				else {
					$skip = 1 if $asm =~ /\d+/;		# nn
				}
			}

			push @test, sprintf(" %-31s; Error", $asm) unless $skip;
		}
	}
	
	open(my $fh, ">", "${output_basename}_${cpu}_err.asm") or die $!;
	say $fh join("\n", sort @test);
}


sub add {
	my($cpu, $opcode) = @_;
	
use Data::Dump 'dump'; dump $opcode;
	
	#say "$cpu\t$opcode->asm\t$bytes" if $opcode->asm =~ /ld hl, sp\+/;
	
	# special case for intel: jr and djnz %j is converted to %m
	if ($opcode->cpu =~ /^80/ && $opcode->asm =~ /^(jr|djnz)/) {
		$opcode->{asm} =~ s/%j/%m/;
	}
	
	if ($opcode->asm =~ /%c/) {
		my @const = sort {$a <=> $b} @{$opcode->const};
		for my $c (@const) {
			my $opcode1 = clone($opcode);
			$opcode1->{asm} =~ s/%c/$c/;
				
			for my $op (@{$opcode->opcodes}) {
				for my $byte (@$op) {
					if ($byte =~ s/%c/$c/g) {
						$byte = eval($byte); $@ and die $@;
					}
				}
			}
			add($cpu, $opcode1);
		}
		
		# create error cases
		my %const; $const{$_}=1 for @const;
		for my $c (min(@const)-1 .. max(@const)+1) {
			if (!$const{$c}) {
				my $asm1 = $opcode->asm =~ s/%c/$c/r;
				$all_opcodes{ALL}{$asm1} = 1;
			}
		}
	}
#	elsif ($opcode->asm =~ /^ldh .*\(c\)/) {
#		add($cpu, $opcode->asm =~ s/\(c\)/( c )/r, $bytes);	# ( c ) to break recursion
#		add($cpu, $opcode->asm =~ s/ldh /ld /r =~ s/\(c\)/(0xff00+c)/r, $bytes);
#	}
#	elsif ($opcode->asm =~ /%d/) {
#		my $asm1 = $opcode->asm =~ s/\+%d/+126/r;
#		my $bytes1 = $bytes =~ s/%d/7E/r =~ s/%D/7F/r;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/\+%d/+0/r;
#		$bytes1 = $bytes =~ s/%d/00/r =~ s/%D/01/r;
#		add($cpu, $asm1, $bytes1);
#
#		$asm1 = $opcode->asm =~ s/\+%d/-128/r;
#		$bytes1 = $bytes =~ s/%d/80/r =~ s/%D/81/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($opcode->asm =~ /%u/) {
#		my $asm1 = $opcode->asm =~ s/\+%u/+0/r;
#		my $bytes1 = $bytes =~ s/%u/00/r;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/\+%u/+128/r;
#		$bytes1 = $bytes =~ s/%u/80/r;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/\+%u/+255/r;
#		$bytes1 = $bytes =~ s/%u/FF/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	# must be 1-byte opcode so that call to __z80asm__add_sp_s with defb %s after
#	# is diassembled correctly during z80asm tests in cpu.t
#	elsif ($asm =~ /%s/) {	
#		my $asm1 = $opcode->asm =~ s/%s/-128/r;
#		$asm1 =~ s/\+-/-/g;
#		my $bytes1 = $bytes =~ s/%s 00/80 FF/r;
#		$bytes1 =~ s/%s/80/;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%s/0/r;
#		$asm1 =~ s/\+-/-/g;
#		$bytes1 = $bytes =~ s/%s 00/00 00/r;
#		$bytes1 =~ s/%s/00/;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%s/126/r;
#		$bytes1 = $bytes =~ s/%s 00/7E 00/r;
#		$bytes1 =~ s/%s/7E/;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($asm =~ /%n/) {
#		my $asm1 = $opcode->asm =~ s/%n/-128/gr;
#		my $bytes1 = $bytes =~ s/%n/80/gr;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%n/0/gr;
#		$bytes1 = $bytes =~ s/%n/00/gr;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%n/127/gr;
#		$bytes1 = $bytes =~ s/%n/7F/gr;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%n/255/gr;
#		$bytes1 = $bytes =~ s/%n/FF/gr;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($asm =~ /%h/) {
#		my $asm1 = $opcode->asm =~ s/%h/0/gr;
#		my $bytes1 = $bytes =~ s/%h/00/gr;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%h/127/gr;
#		$bytes1 = $bytes =~ s/%h/7F/gr;
#		add($cpu, $asm1, $bytes1);
		#
#		$asm1 = $opcode->asm =~ s/%h/255/gr;
#		$bytes1 = $bytes =~ s/%h/FF/gr;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($bytes =~ /%m %m %m %m/) {
#		my $asm1 = $opcode->asm =~ s/%m/0x12345678/r;
#		my $bytes1 = $bytes =~ s/%m/78/r;
#		$bytes1 = $bytes1 =~ s/%m/56/r;
#		$bytes1 = $bytes1 =~ s/%m/34/r;
#		$bytes1 = $bytes1 =~ s/%m/12/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($bytes =~ /%m %m %m/) {
#		my $asm1 = $opcode->asm =~ s/%m/0x123456/r;
#		my $bytes1 = $bytes =~ s/%m/56/r;
#		$bytes1 = $bytes1 =~ s/%m/34/r;
#		$bytes1 = $bytes1 =~ s/%m/12/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($bytes =~ /%m1 %m1/) {
#		my $asm1 = $opcode->asm =~ s/%m/0x1234/r;
#		my $bytes1 = $bytes =~ s/%m1 %m1/35 12/gr;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($bytes =~ /%m %m/) {
#		my $asm1 = $opcode->asm =~ s/%m/0x1234/r;
#		my $bytes1 = $bytes =~ s/%m %m/34 12/gr;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($asm =~ /%M/) {
#		my $asm1 = $opcode->asm =~ s/%M/0x1234/r;
#		my $bytes1 = $bytes =~ s/%M/12/r;
#		$bytes1 = $bytes1 =~ s/%M/34/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($bytes =~ /^[0-9A-F]{2} %j [0-9A-F]{2} %j$/) {
#		my $asm1 = $opcode->asm =~ s/%j/ASMPC/r;
#		my $bytes1 = $bytes =~ s/%j/FE/r;
#		$bytes1 = $bytes1 =~ s/%j/FC/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($asm =~ /%j/) {
#		my $asm1 = $opcode->asm =~ s/%j/ASMPC/r;
#		my $dist = sprintf("%02X", (- scalar(@bytes)) & 0xFF);
#		my $bytes1 = $bytes =~ s/%j/$dist/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($asm =~ /%J/) {
#		my $asm1 = $opcode->asm =~ s/%J/ASMPC/r;
#		my $dist = sprintf("%04X", (- scalar(@bytes)) & 0xFFFF);
#		my $bytes1 = $bytes =~ s/%J %J/substr($dist,2,2)." ".substr($dist,0,2)/er;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($asm =~ /%c/) {
#		my $bytes1 = $bytes =~ s/%c\((\d+.*?\d+)\)/%c/r;
#		my @range = eval($1); $@ and die $@;
#		for my $c (@range) {
#			my $asm2 = $opcode->asm =~ s/%c/$c/r;
#			my @bytes2 = split(' ', $bytes1);
#			for (@bytes2) {
#				if (s/%c/$c/g) {
#					$_ = sprintf("%02X", eval($_)); $@ and die $@;
#				}
#			}
#			add($cpu, $asm2, "@bytes2");
#		}
		#
#		# create error cases
#		for my $c ($range[0]-1, $range[-1]+1) {
#			my $asm1 = $opcode->asm =~ s/%c/$c/r;
#			$all_opcodes{ALL}{$asm1} = 1;
#		}
#	}
	else {
		my @bytes;
		for my $op (@{$opcode->opcodes}) {
			for my $byte (@$op) {
				if ($byte =~ /^\d+$/) {
					push @bytes, sprintf("%02X", $byte);
				}
				else {
					push @bytes, $byte;
				}
			}
		}
		push @test, sprintf(" %-31s; %s", $opcode->asm, "@bytes");
		$all_opcodes{$cpu}{$opcode->asm} = 1;
		$all_opcodes{ALL}{$opcode->asm} = 1;
	}
}

sub compute_labels {
	my($cpu, @test) = @_;
	my $asmpc = 0;
	for (@test) {
		my($asm, $bytes) = split(/;/, $_, 2);
		my @bytes = split ' ', $bytes;
		my $num_bytes = scalar(@bytes);
		if ($bytes =~ /\@/) {
			if ($cpu eq 'ez80') {
				$num_bytes += 2;
			}
			else {
				$num_bytes += 1;
			}
		}
		
		while ($bytes =~ /%t(\d*) %t\1 %t\1/) {
			my $before = $`; my @before = split ' ', $before;
			my $after  = $'; my @after  = split ' ', $after;
			my $target = $asmpc + $num_bytes - ($1 || 0);
			@bytes = (@before, sprintf("%02X", ($target) & 0xFF),
							   sprintf("%02X", ($target >> 8) & 0xFF),
							   sprintf("%02X", ($target >> 16) & 0xFF), @after);
			$bytes = join ' ', @bytes;
		}
		
		while ($bytes =~ /%t(\d*) %t\1/) {
			my $before = $`; my @before = split ' ', $before;
			my $after  = $'; my @after  = split ' ', $after;
			my $target = $asmpc + $num_bytes - ($1 || 0);
			@bytes = (@before, sprintf("%02X", ($target) & 0xFF),
							   sprintf("%02X", ($target >> 8) & 0xFF), @after);
			$bytes = join ' ', @bytes;
		}
		
		while ($bytes =~ /%t(\d*)/) {
			my $before = $`; my @before = split ' ', $before;
			my $after  = $'; my @after  = split ' ', $after;
			my $target = $asmpc + $num_bytes - ($1 || 0) - ($asmpc + scalar(@before) + 1);
			@bytes = (@before, sprintf("%02X", ($target) & 0xFF), @after);
			$bytes = join ' ', @bytes;
		}
		
		die $bytes if $bytes =~ /%/;

		$asmpc += $num_bytes;
		
		$_ = "$asm; @bytes";
	}
	return @test;
}
