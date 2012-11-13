package MM::Net::IPAddress;

use strict;
use warnings;

# We don't want the pure Perl implementation - it's slow
use Math::BigInt::GMP;

use Carp qw( confess );
use NetAddr::IP::Util qw( inet_any2n );
use NetAddr::IP;
use Scalar::Util qw( blessed );

# Using this currently breaks overloading - see
# https://rt.cpan.org/Ticket/Display.html?id=50938
#
#use namespace::autoclean;

use overload (
    q{""} => 'as_string',
    '<=>' => '_compare_overload',
);

use Moose;

has _ip => (
    is      => 'ro',
    isa     => 'NetAddr::IP',
    handles => {
        version     => 'version',
        mask_length => 'bits',
    },
);

override BUILDARGS => sub {
    my $class = shift;

    my $p = super();

    my $ip
        = $p->{_ip} // ( $p->{version} && $p->{version} == 6 )
        ? NetAddr::IP->new6( $p->{address} )
        : NetAddr::IP->new( $p->{address} )
        or die "Invalid address: $p->{address}";

    return { _ip => $ip };
};

sub new_from_string {
    my $class = shift;
    my %p     = @_;

    return $class->new( address => $p{string}, %p );
}

sub new_from_integer {
    my $class = shift;
    my %p     = @_;

    return $class->new( address => delete $p{integer}, %p );
}

sub as_string {
    my $self = shift;

    return $self->version() == 6
        ? lc $self->_ip()->short()
        : $self->_ip()->addr();
}

sub as_integer {
    my $self = shift;

    return $self->version() == 4
        ? ( scalar $self->_ip()->numeric() ) + 0
        : scalar $self->_ip()->bigint();
}

sub as_binary {
    my $self = shift;

    return inet_any2n( $self->as_string );
}

sub as_ipv4_string {
    my $self = shift;

    return $self->as_string() if $self->version() == 4;

    confess
        'Cannot represent IP address larger than 2**32-1 as an IPv4 string'
        if $self->as_integer() >= 2**32;

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer(),
        version => 4,
    )->as_string();
}

sub as_bit_string {
    my $self = shift;

    if ( $self->version == 6 ) {
        my $bin = $self->as_integer()->as_bin();

        $bin =~ s/^0b//;
        return sprintf( '%0128s', $bin );
    }
    else {
        return sprintf( '%032b', $self->as_integer );
    }
}

sub next_ip {
    my $self = shift;

    my $bits = $self->mask_length();
    confess "$self is the last address in its range"
        if $self->as_integer() == do { use bigint; ( 2**$bits - 1 ) };

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer() + 1,
        version => $self->version()
    );
}

sub previous_ip {
    my $self = shift;

    confess "$self is the first address in its range"
        if $self->as_integer() == 0;

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer() - 1,
        version => $self->version(),
    );
}

sub _compare_overload {
    my $self  = shift;
    my $other = shift;
    my $flip  = shift() ? -1 : 1;

    confess 'Cannot compare unless both objects are '
        . __PACKAGE__
        . ' objects'
        unless blessed $self
        && blessed $other
        && eval { $self->isa(__PACKAGE__) && $other->isa(__PACKAGE__) };

    return $flip * ( $self->as_integer() <=> $other->as_integer() );
}

__PACKAGE__->meta()->make_immutable();

1;
