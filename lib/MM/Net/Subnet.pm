package MM::Net::Subnet;

use strict;
use warnings;
use namespace::autoclean;

# We don't want the pure Perl implementation - it's slow
use Math::BigInt::GMP;

use List::AllUtils qw( any first );
use MM::Net::IPAddress;
use NetAddr::IP;

use Moose;

has _netmask => (
    is      => 'ro',
    isa     => 'NetAddr::IP',
    handles => {
        netmask     => 'masklen',
        mask_length => 'bits',
        version     => 'version',
    },
);

has first => (
    is       => 'ro',
    isa      => 'MM::Net::IPAddress',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_first',
);

has last => (
    is       => 'ro',
    isa      => 'MM::Net::IPAddress',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_last',
);

override BUILDARGS => sub {
    my $self = shift;

    my $p = super();

    my $constructor = $p->{version} && $p->{version} == 6 ? 'new6' : 'new';

    my $nm = NetAddr::IP->$constructor( $p->{subnet} )
        or die "Invalid subnet specifier - [$p->{subnet}]";

    return { _netmask => $nm };
};

{
    my %max = (
        32  => 2**32 - 1,
        128 => do { use bigint; 2**128 - 1 },
    );

    sub max_netmask {
        my $self = shift;

        my $base = $self->first()->as_integer();

        my $netmask = $self->netmask();

        my $bits = $self->_netmask()->bits();
        while ($netmask) {
            my $mask = do {
                use bigint;
                ( ~( 2**( $bits - $netmask ) - 1 ) & $max{$bits} );
            };

            last if ( $base & $mask ) != $base;

            $netmask--;
        }

        return $netmask + 1;
    }
}

sub iterator {
    my $self = shift;

    my $version = $self->version();
    my $current = $self->first()->as_integer();
    my $last    = $self->last()->as_integer();

    return sub {
        return if $current > $last;

        MM::Net::IPAddress->new_from_integer(
            integer => $current++,
            version => $version,
        );
    };
}

sub as_string {
    my $self = shift;

    my $netmask = $self->_netmask();

    return $self->version() == 6
        ? ( join '/', lc $netmask->short(), $netmask->masklen() )
        : $netmask->cidr();
}

sub _build_first {
    my $self = shift;

    return MM::Net::IPAddress->new(
        address => $self->_netmask()->network()->addr(),
        version => $self->version(),
    );
}

sub _build_last {
    my $self = shift;

    return MM::Net::IPAddress->new(
        address => $self->_netmask()->broadcast()->addr(),
        version => $self->version(),
    );
}

sub _remove_private_subnets_from_range {
    my $class   = shift;
    my $first   = shift;
    my $last    = shift;
    my $version = shift;

    my @ranges;

    $class->_remove_private_subnets_from_range_r(
        $first,
        $last,
        $version,
        \@ranges
    );

    return @ranges;
}

{
    my @reserved_4 = qw(
        10.0.0.0/8
        127.0.0.0/8
        169.254.0.0/16
        172.16.0.0/12
        192.0.2.0/24
        192.88.99.0/24
        192.168.0.0/16
    );

    my @reserved_6 = qw(
        10.0.0.0/8
        127.0.0.0/8
        169.254.0.0/16
        172.16.0.0/12
        192.0.2.0/24
        192.88.99.0/24
        192.168.0.0/16
        fc00::/7
        fe80::/10
        ff00::/8
    );

    my %reserved_networks = (
        4 => [
            map { MM::Net::Subnet->new( subnet => $_, version => 4 ) }
                @reserved_4,
        ],
        6 => [
            map { MM::Net::Subnet->new( subnet => $_, version => 6 ) }
                @reserved_6,
        ],
    );

    sub _remove_private_subnets_from_range_r {
        my $class   = shift;
        my $first   = shift;
        my $last    = shift;
        my $version = shift;
        my $ranges  = shift;

        for my $pn ( @{ $reserved_networks{$version} } ) {
            my $private_first = $pn->first();
            my $private_last  = $pn->last();

            next if ( $last < $private_first || $first > $private_last );

            if ( $first >= $private_first and $last <= $private_last ) {

                # just remove the range, it is completely in a private network
                return;
            }

            $class->_remove_private_subnets_from_range_r(
                $first,
                $private_first->previous_ip(),
                $version,
                $ranges,
            ) if ( $first < $private_first );

            $class->_remove_private_subnets_from_range_r(
                $private_last->next_ip(),
                $last,
                $version,
                $ranges,
            ) if ( $last > $private_last );
            return;
        }

        push @{$ranges}, [ $first, $last ];
    }
}

sub range_as_subnets {
    my $class = shift;
    my $first = shift;
    my $last  = shift;

    my $version = ( any { /:/ } $first, $last ) ? 6 : 4;

    $first = MM::Net::IPAddress->new(
        address => $first,
        version => $version,
    ) unless ref $first;

    $last = MM::Net::IPAddress->new(
        address => $last,
        version => $version,
    ) unless ref $last;

    my @ranges = $class->_remove_private_subnets_from_range(
        $first,
        $last,
        $version
    );

    my @subnets;
    for my $range (@ranges) {
        push @subnets, $class->_split_one_range( @{$range} );
    }

    return @subnets;
}

sub _split_one_range {
    my $class = shift;
    my $first = shift;
    my $last  = shift;

    my $version = $first->version();

    my $bits = $version == 6 ? 128 : 32;

    my @subnets;
    while ( $first <= $last ) {
        my $smallest_subnet = MM::Net::Subnet->new(
            subnet  => $first . '/' . $bits,
            version => $version,
        );

        my $max_network = first { $_->last() <= $last } (
            map {
                MM::Net::Subnet->new(
                    subnet  => $first . '/' . $_,
                    version => $version,
                    )
            } $smallest_subnet->max_netmask() .. $bits
        );

        push @subnets, $max_network;

        $first = $max_network->last()->next_ip();
    }

    return @subnets;
}

__PACKAGE__->meta()->make_immutable();

1;
