#!/usr/bin/env perl

#------------------------------------------------------------------------------
# Build text table representation of opcodes.yaml
#------------------------------------------------------------------------------

use Modern::Perl;
use YAML::Tiny;
use Text::Table;
use Clone 'clone';
use warnings FATAL => 'uninitialized'; 
use Carp (); 
$SIG{__DIE__} = \&Carp::confess;
use Data::Dump 'dump';

@ARGV==2 or die "Usage: $0 input_file.yaml output_file.txt\n";
my($input_file, $output_file) = @ARGV;

my $yaml = YAML::Tiny->read($input_file);
my $opcodes = $yaml->[0];

my $sep = \"|";

$opcodes = expand_consts($opcodes);
my $opcode_table = make_opcode_table($opcodes);
my $hex_table = make_hex_table($opcodes);

open(my $fh, ">", $output_file) or die $!;
print $fh $opcode_table->rule('=');
print $fh $opcode_table->title;
print $fh $opcode_table->rule('=');
print $fh $opcode_table->body;
print $fh $opcode_table->rule('=');
print $fh "\n\n";
print $fh $hex_table->rule('=');
print $fh $hex_table->title;
print $fh $hex_table->rule('=');
print $fh $hex_table->body;
print $fh $hex_table->rule('=');


sub expand_consts {
	my($opcodes_in) = @_;
	my $opcodes_out = {opcodes=>{}};

	for my $asm (sort keys %{$opcodes_in->{opcodes}}) {
		for my $cpu (sort keys %{$opcodes_in->{opcodes}{$asm}}) {
			my @ops = @{clone($opcodes_in->{opcodes}{$asm}{$cpu}{ops})};
			
			if ($asm =~ /%c/) {
				my @range = find_range($asm, $cpu, @ops);
				for my $c (@range) {
					my($asm1, @ops1) = replace_const($c, $asm, @ops);
					if ($asm =~ /^rst/ && $cpu =~ /^r2ka|^r3k/ && 
					    ($c == 0 || $c == 8 || $c == 0x30)) {
						$opcodes_out->{opcodes}{$asm1}{$cpu} = {ops => [[0xCD, $c, 0]]};
					}
					else {    
						$opcodes_out->{opcodes}{$asm1}{$cpu} = {ops => \@ops1};
					}
				}
			}
			else {
				$opcodes_out->{opcodes}{$asm}{$cpu} = {ops => \@ops};
			}
		}
	}
	
	return $opcodes_out;
}	

sub find_range {
	my($asm, $cpu, @ops) = @_;
	
	if ($asm =~ / rst (\.(s|sil|l|lis))? \s+ %c /x) {
		return (0x00, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38);
	}
	else {
		for my $op (@ops) {
			for my $byte (@$op) {
				if ($byte =~ / %c \( (\d+) \.\. (\d+) \) /x) {
					return ($1 .. $2);
				}
				elsif ($byte =~ / %c \( ( \d+ (, \d+)* ) \) /x) {
					return (eval $1);
				}
			}
		}
	}
	
	die "no range found in $asm, $cpu";
}

sub replace_const {
	my($c, $asm, @ops) = @_;

	my $c_str = ($asm =~ /^rst/ || $c >= 10) ? sprintf("%02Xh", $c) : $c;
	$asm =~ s/%c/$c_str/;
	
	@ops = @{clone(\@ops)};
	for my $op (@ops) {
		for my $byte (@$op) {
			if ($byte =~ s/ %c ( \( .*? \) )? /$c/xg) {
				$byte = eval($byte); die "$byte: $@" if $@;
			}
		}
	}
	
	return ($asm, @ops);
}
	
sub make_opcode_table {
	my($opcodes) = @_;
	my $tb = Text::Table->new($sep, "Assembly", $sep, "CPUs", $sep);

	for my $asm (sort keys %{$opcodes->{opcodes}}) {
		my @cpus;
		for my $cpu (sort keys %{$opcodes->{opcodes}{'nop'}}) {	# always exists
			if (exists $opcodes->{opcodes}{$asm}{$cpu}) {
				push @cpus, $cpu;
			}
			else {
				push @cpus, "-".(" " x (length($cpu)-1));
			}
		}
		$tb->add($asm, "@cpus");
	}
	return $tb;
}

sub make_hex_table {
	my($opcodes) = @_;
	my $tb = Text::Table->new($sep, "Assembly", $sep, "CPU", $sep, "Opcodes", $sep);

	for my $asm (sort keys %{$opcodes->{opcodes}}) {
		for my $cpu (sort keys %{$opcodes->{opcodes}{$asm}}) {
			my @ops = @{$opcodes->{opcodes}{$asm}{$cpu}{ops}};
			my @bytes;
			for my $op (@ops) {
				for my $byte (@$op) {
					next unless defined $byte;
					if ($byte =~ /^\d+$/) {
						push @bytes, sprintf("%02X", $byte);
					}
					else {
						push @bytes, $byte;
					}
				}
			}
			$tb->add($asm, $cpu, "@bytes");
		}
	}
	return $tb;
}

