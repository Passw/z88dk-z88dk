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
use Data::Dump 'dump'; 
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
		#say "$cpu\t$asm" if $opcode->asm =~ /ld \(sp\+/;

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
	
	#say "$cpu\t$opcode->asm\t$bytes" if $opcode->asm =~ /ld hl, sp\+/;
	
	# special case for intel: jr and djnz %j is converted to %m
	if ($opcode->cpu =~ /^80/ && $opcode->asm =~ /^(jr|djnz)/) {
		$opcode = $opcode->clone(sub { s/%j/%m/; }, sub {});
	}
	
	if ($opcode->asm =~ /%c/) {
		my @const = sort {$a <=> $b} @{$opcode->const};
		for my $c (@const) {
			my $opcode1 = $opcode->clone(sub { s/%c/$c/; }, 
									     sub { if (s/%c/$c/g) {
										  		  $_ = eval($_); $@ and die $@;
											   }});
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
	elsif ($opcode->asm =~ /%n/) {
		add($cpu, $opcode->clone(sub {s/%n/-128/}, sub {s/%n/0x80/e}));
		add($cpu, $opcode->clone(sub {s/%n/0/},    sub {s/%n/0x00/e}));
		add($cpu, $opcode->clone(sub {s/%n/127/},  sub {s/%n/0x7F/e}));
		add($cpu, $opcode->clone(sub {s/%n/255/},  sub {s/%n/0xFF/e}));
	}
	elsif ($opcode->asm =~ /%m/) {
		add($cpu, $opcode->clone(sub {s/%m/0x12345678/}, 
								 sub {s/%m1/0x79/e;
								      s/%m1/0x56/e;
								      s/%m1/0x34/e;
								      s/%m1/0x12/e;
								      s/%m/0x78/e;
								      s/%m/0x56/e;
								      s/%m/0x34/e;
								      s/%m/0x12/e}));
	}
	elsif ($opcode->asm =~ /%M/) {
		add($cpu, $opcode->clone(sub {s/%M/0x1234/}, 
								 sub {s/%M/0x12/e;
								      s/%M/0x34/e}));
	}
	# must be 1-byte opcode so that call to __z80asm__add_sp_s with defb %s after
	# is diassembled correctly during z80asm tests in cpu.t
	elsif ($opcode->asm =~ /%s/) {	
		add($cpu, $opcode->clone(sub {s/%s/-128/; s/\+-/-/}, sub {s/%s/0x80/e}));
#		my $bytes1 = $bytes =~ s/%s 00/80 FF/r;

		add($cpu, $opcode->clone(sub {s/%s/0/; s/\+0//}, sub {s/%s/0x00/e}));
#		$bytes1 = $bytes =~ s/%s 00/00 00/r;

		# 7F is a prefix in r4k and r5k, is not single-opcode; use 7E instead
		add($cpu, $opcode->clone(sub {s/%s/126/}, sub {s/%s/0x7E/e}));
#		$bytes1 = $bytes =~ s/%s 00/7E 00/r;
	}
	elsif ($opcode->asm =~ /%u/) {
		add($cpu, $opcode->clone(sub {s/%u/0/; s/\+0//}, sub {s/%u/0x00/e}));
		add($cpu, $opcode->clone(sub {s/%u/128/}, sub {s/%u/0x80/e}));
		add($cpu, $opcode->clone(sub {s/%u/255/}, sub {s/%u/0xFF/e}));
	}
	elsif ($opcode->asm =~ /%d/) {
		add($cpu, $opcode->clone(sub {s/%d/126/}, sub {s/%d/0x7E/e; s/%D/0x7F/e}));
		add($cpu, $opcode->clone(sub {s/%d/0/; s/\+0//}, sub {s/%d/0x00/e; s/%D/0x01/e}));
		add($cpu, $opcode->clone(sub {s/%d/-128/; s/\+-/-/}, sub {s/%d/0x80/e; s/%D/0x81/e}));
	}
	elsif ($opcode->asm =~ /%j/) {
		my $dist = -scalar($opcode->bytes);
		add($cpu, $opcode->clone(sub {s/%j/ASMPC/}, sub {s/%j/$dist & 0xFF/e}));
	}
	elsif ($opcode->asm =~ /%J/) {
		my $dist = -scalar($opcode->bytes);
		add($cpu, $opcode->clone(sub {s/%J/ASMPC/}, sub {s/%J/$dist & 0xFF/e; s/%J/($dist>>8) & 0xFF/e}));
	}
	elsif ($opcode->asm =~ /%h/) {
		add($cpu, $opcode->clone(sub {s/%h/0/}, sub {s/%h/0x00/e}));
		add($cpu, $opcode->clone(sub {s/%h/127/}, sub {s/%h/0x7F/e}));
		add($cpu, $opcode->clone(sub {s/%h/255/}, sub {s/%h/0xFF/e}));
	}
#	elsif ($opcode->asm =~ /^ldh .*\(c\)/) {
#		add($cpu, $opcode->asm =~ s/\(c\)/( c )/r, $bytes);	# ( c ) to break recursion
#		add($cpu, $opcode->asm =~ s/ldh /ld /r =~ s/\(c\)/(0xff00+c)/r, $bytes);
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
#	elsif ($bytes =~ /^[0-9A-F]{2} %j [0-9A-F]{2} %j$/) {
#		my $asm1 = $opcode->asm =~ s/%j/ASMPC/r;
#		my $bytes1 = $bytes =~ s/%j/FE/r;
#		$bytes1 = $bytes1 =~ s/%j/FC/r;
#		add($cpu, $asm1, $bytes1);
#	}
#	elsif ($opcode->asm =~ /%c/) {
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
				elsif ($byte =~ /^@/) {		# call address
					push @bytes, $byte;
				}
				elsif ($byte =~ /^%t/) {	# temp address
					push @bytes, $byte;
				}
				else {
					die dump $opcode;
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
