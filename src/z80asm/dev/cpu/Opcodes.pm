package Opcode;

#------------------------------------------------------------------------------
# Build CPU tables
# asm placeholders:
#	%s	signed byte
#	%n	unsigned byte
#   %h  high page offset
#	%m	unsigned word - 16, 24 or 32 bits
#	%M	unsigned word, big-endian
#	%j	jr offset
#	%c	constant (im, bit, rst, ...)
#	%d	signed register indirect offset
#	%D	%d+1
#	%u	unsigned register indirect offset
#	%t	temp jump label to end of statement; %t3 to end of statement - 3
#------------------------------------------------------------------------------

use Object::Tiny qw( asm cpu synthetic opcodes );

# all CPUs
my @CPUS = (qw(
	z80
	z80_strict
	z80n
	z180
	ez80
	ez80_z80
	r800
	r2ka
	r3k
	r4k
	r5k
	8080
	8085
	gbz80
	kc160
	kc160_z80
));

# create constants for each cpu
my %CPUS;
for my $cpu (@CPUS) {
	$CPUS{$cpu} = 1;
	eval "sub cpu_$cpu() { return '$cpu'; }"; $@ and die $@;
}
	
sub new {
	my($class, %args) = @_;
	my $self = bless {}, $class;
	
	$self->{asm} = delete $args{asm} || '';
	
	$self->{cpu} = delete $args{cpu} || cpu_z80;
	$CPUS{$self->cpu} or die "cpu not found: ", $self->cpu;
	
	$self->{synthetic} = delete $args{synthetic} || 0;
	
	# list of opcodes, each list of bytes or %X
	$self->{opcodes} = delete $args{opcodes} || [[]];
	
	%args and die "extra arguments: ", join(" ", keys %args);
	
	return $self;
}

# input/output to data file
sub to_string {
	my($self) = @_;
	my @output = ($self->asm, $self->cpu, $self->synthetic ? "X" : "_");
	my @opcodes;
	for my $opcode (@{$self->opcodes}) {
		my @bytes;
		for my $byte (@$opcode) {
			if ($byte =~ /^\d+$/) {
				push @bytes, sprintf("%02X", $byte);
			}
			else {
				push @bytes, $byte;
			}
		}
		push @opcodes, join(" ", @bytes);
	}
	push @output, join(";", @opcodes);
	my $output = join("|", @output);
	return $output;
}

sub from_string {
	my($class, $str) = @_;
	my $self = Opcode->new;
	chomp($str);
	my @fields = split(/\|/, $str);
}
			
1;
