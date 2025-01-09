#------------------------------------------------------------------------------
# One opcode
#------------------------------------------------------------------------------
package Opcode;

#------------------------------------------------------------------------------
# Build CPU tables
# asm placeholders:
#	%s	signed byte
#	%n	unsigned byte
#   %h  high page offset
#	%m	unsigned word - 16, 24 or 32 bits
#   %M 	%m+1
#	%B	unsigned word, big-endian
#	%j	jr offset
#	%c	constant (im, bit, rst, ...)
#	%d	signed register indirect offset
#	%D  %d+1
#	%u	unsigned register indirect offset
#	%t	temp jump label to end of statement; %t3 to end of statement - 3
#------------------------------------------------------------------------------

use Modern::Perl;
my @fields = 	 qw( asm cpu synthetic undocumented const ops );
use Object::Tiny qw( asm cpu synthetic undocumented const ops );

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

# return list of all CPUS
sub cpus {
	my($class) = @_;
	return sort @CPUS;
}

# create opcode
sub new {
    my($class, %args) = @_;

    my $asm = delete $args{asm} || die "missing asm";
    my $cpu = delete $args{cpu} || die "missing cpu";
    my $synthetic = delete $args{synthetic} || 0;
    my $undocumented = delete $args{undocumented} || 0;
    my $const = delete $args{const} || [];
    my $ops = delete $args{ops} || die "missing ops";
    %args and die "extra arguments: ", join(" ", keys %args);

    my $self = bless { 
        asm => $asm, 
        cpu => $cpu, 
        synthetic => $synthetic, 
        undocumented => $undocumented, 
        const => $const,
        ops => $ops,
    }, $class;
    return $self;
}

# clone opcode, replace asm and bin %X by using passed functions
sub clone {
	my($self, $replace_asm_f, $replace_bytes_f) = @_;
	my $new = Clone::clone($self);
	for ($new->{asm}) {
		$replace_asm_f->();
	}
	for my $op (@{$new->ops}) {
		for (@$op) {
			$replace_bytes_f->();
		}
	}
	return $new;
}

# return list with bytes
sub bytes {
	my($self) = @_;
	my @bytes;
	for my $op (@{$self->ops}) {
		for my $byte (@$op) {
			push @bytes, $byte;
		}
	}
	return @bytes;
}

# input/output to data file
sub titles {
	my($class) = @_;
	return join("|", @fields);
}

sub to_string {
	my($self) = @_;
	my @output = ($self->asm, $self->cpu, 
				  $self->synthetic ? "X" : "_",
				  $self->undocumented ? "U" : "_",
				  join(",", @{$self->const}));
	my @ops;
	for my $op (@{$self->ops}) {
		my @bytes;
		for my $byte (@$op) {
			if ($byte =~ /^\d+$/) {
				push @bytes, sprintf("%02X", $byte);
			}
			else {
				push @bytes, $byte;
			}
		}
		push @ops, join(" ", @bytes);
	}
	push @output, join(";", @ops);
	my $output = join("|", @output);
	return $output;
}

sub from_string {
	my($class, $str) = @_;
	chomp($str);
	my @data = split(/\|/, $str);
	@data == 6 or die "insufficient data: $str";
	my @ops = split(/;/, $data[5]);
	for (@ops) {
		my @bytes = split(' ', $_);
		for (@bytes) {
			if (/^[0-9a-f]+$/i) {
				$_ = hex($_);
			}
		}
		$_ = \@bytes;
	}
	my $self = $class->new(
						asm => $data[0], 
						cpu => $data[1], 
						synthetic => $data[2] =~ /x/i ? 1 : 0,
						undocumented=> $data[3] =~ /u/i ? 1 : 0,
						const => [split(/,/, $data[4])],
						ops => \@ops);
	return $self;
}

#------------------------------------------------------------------------------
# List of all opcode indexed by asm, cpu
#------------------------------------------------------------------------------
package Opcodes;

use Modern::Perl;
use Object::Tiny qw( opcodes );

# create new Opcodes object
sub new {
    my($class, %args) = @_;
    my $opcodes = delete $args{opcodes} || {};
    %args and die "extra arguments: ", join(" ", keys %args);
    my $self = bless { opcodes => $opcodes }, $class;
    return $self;
}

sub add {
	my($self, $opcode) = @_;
	my $extended = ($opcode->synthetic || $opcode->undocumented) ? 1 : 0;
	if ($self->exists($opcode->asm, $opcode->cpu) &&
	    $self->opcodes->{$opcode->asm}{$opcode->cpu}[$extended]) {
		die "opcode already exists: ", 
			$self->opcodes->{$opcode->asm}{$opcode->cpu}[$extended]->to_string, 
			" ",
			$opcode->to_string;
	}
	
	$self->opcodes->{$opcode->asm}{$opcode->cpu}[$extended] = $opcode;
}

sub exists {
	my($self, $asm, $cpu) = @_;
	if ($self->opcodes->{$asm} &&
		$self->opcodes->{$asm}{$cpu}) {
		if ($self->opcodes->{$asm}{$cpu}[0] || 
			$self->opcodes->{$asm}{$cpu}[1]) {
			return 1;
		}
		else {
			return 0;
		}
	}
	else {
		return 0;
	}
}	

# input/output to data file
sub write_file {
	my($self, $file) = @_;
	open(my $fh, ">", $file) or die "write $file: $!";
	say $fh Opcode->titles;
	for my $asm (sort keys %{$self->opcodes}) {
		for my $cpu (sort keys %{$self->opcodes->{$asm}}) {
			for my $extended (0..1) {
				my $opcode = $self->opcodes->{$asm}{$cpu}[$extended];
				if ($opcode) {
					say $fh $opcode->to_string;
				}
			}
		}
	}
}

sub read_file {
	my($class, $file) = @_;
	my $self = $class->new;
	open(my $fh, "<", $file) or die "read $file: $!";
	
	my $titles = <$fh>;
	chomp $titles;
	$titles eq Opcode->titles or die "invalid data file $file";
	
	while (<$fh>) {
		my $opcode = Opcode->from_string($_);
		$self->add($opcode);
	}
	return $self;
}

1;
