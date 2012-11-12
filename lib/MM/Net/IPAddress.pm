package MM::Net::IPAddress;

use strict;
use warnings;

# We don't want the pure Perl implementation - it's slow
use Math::BigInt::GMP;

use Carp qw( confess );
use Scalar::Util qw( blessed );

# Using this currently breaks overloading - see
# https://rt.cpan.org/Ticket/Display.html?id=50938
#
#use namespace::autoclean;

use overload (
    q{""} => 'as_string',
    '<=>' => '_compare_overload',
);

use Net::IP qw( ip_inttobin ip_bintoip );

use Moose;

has _ip => (
    is      => 'ro',
    isa     => 'Net::IP',
    handles => {
        as_binary => 'binip',
        version   => 'version',
    },
);

override BUILDARGS => sub {
    my $class = shift;

    my $p = super();

    my $ip = $p->{_ip} // Net::IP->new(
        $p->{address},
        $p->{version} // (),
    ) or die "Invalid address: $p->{address}";

    return { _ip => $ip };
};

sub new_from_integer {
    my $class = shift;
    my %p     = @_;

    my @version = $p{version} // ();

    return $class->new(
        address => ip_bintoip(
            ip_inttobin( $p{integer}, @version ),
            @version,
        ),
        ( @version ? ( version => $version[0] ) : () ),
    );
}

sub mask_length {
    my $self = shift;

    return $self->version() == 6 ? 128 : 32;
}

sub as_string {
    my $self = shift;

    return $self->_ip()->version() == 6
        ? $self->_ip()->short()
        : $self->_ip()->ip();
}

sub as_ipv4_string {
    my $self = shift;

    return $self->as_string() if $self->_ip()->version() == 4;

    confess 'Cannot represent IP address larger than 2**32-1 as an IPv4 string'
        if $self->as_integer() >= 2**32;

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer(),
        version => 4,
    )->as_string();
}

sub as_integer {
    my $self = shift;

    my $integer = $self->_ip()->intip();
    return $integer if defined $integer;

    # Net::IP has some brain damage with regards to 0.0.0.0
    return $self->mask_length() == 128 ? Math::BigInt->new(0) : 0;
}

sub as_bit_string {
    my $self = shift;

    my $integer = $self->as_integer();
    if ( $self->mask_length() == 128 ) {
        my $bin = $integer->as_bin();
        $bin =~ s/^0b//;

        return sprintf( '%0128s', $bin );
    }
    else {
        return sprintf( '%032b', $self->as_integer() );
    }
}

sub next_ip {
    my $self = shift;

    my $ip = $self->_ip();

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

    my $ip = $self->_ip();

    confess "$self is the first address in its range"
        if $self->as_integer() == 0;

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer() - 1,
        version => $self->version()
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
