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

    return MM::Net::IPAddress->new_from_string(
        string  => $self->_netmask()->network()->addr(),
        version => $self->version(),
    );
}

sub _build_last {
    my $self = shift;

    return MM::Net::IPAddress->new_from_string(
        string  => $self->_netmask()->broadcast()->addr(),
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

    $first = MM::Net::IPAddress->new_from_string(
        string  => $first,
        version => $version,
    ) unless ref $first;

    $last = MM::Net::IPAddress->new_from_string(
        string  => $last,
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

# ABSTRACT: An object representing a single IP address (4 or 6) subnet

__END__

=head1 SYNOPSIS

  my $subnet = MM::Net::Subnet->new( subnet => '1.0.0.0/24' );
  print $subnet->as_string();   # 1.0.0.0/28
  print $subnet->netmask();     # 24
  print $subnet->mask_length(); # 32
  print $subnet->version();     # 4

  my $first = $subnet->first();
  print $first->as_string();    # 1.0.0.0

  my $last = $subnet->first();
  print $last->as_string();     # 1.0.0.255

  my $iterator = $subnet->iterator();
  while ( my $ip = $iterator->() ) { ... }

  my $subnet = MM::Net::Subnet->new( subnet => '1.0.0.4/32' );
  print $subnet->max_netmask(); # 30

  # All methods work with IPv4 and IPv6 subnets
  my $subnet = MM::Net::Subnet->new( subnet => 'a800:f000::/20' );

  my @subnets = MM::Net::Subnet->range_as_subnets( '1.1.1.1', '1.1.1.32' );
  print $_->as_string, "\n" for @subnets;
  # 1.1.1.1/32
  # 1.1.1.2/31
  # 1.1.1.4/30
  # 1.1.1.8/29
  # 1.1.1.16/28
  # 1.1.1.32/32

=head1 DESCRIPTION

Objects of this class represent an IP address subnet. It can handle both IPv4
and IPv6 subnets. It provides various methods for getting information about
the subnet.

For IPv6, it uses big integers (via Math::BigInt) to represent the numeric
value of an address as needed.

This module is currently a thin wrapper around NetAddr::IP but that could
change in the future.

=head1 METHODS

This class provides the following methods:

=head2 MM::Net::Subnet->new( ... )

This method takes a C<subnet> parameter and an optional C<version>
parameter. The C<subnet> parameter should be a string representation of an IP
address subnet.

The C<version> parameter should be either C<4> or C<6>, but you don't really need
this unless you're trying to force a dotted quad to be interpreted as an IPv6
subnet or to a force an IPv6 address colon-separated hex number to be
interpreted as an IPv4 subnet.

=head2 $subnet->as_string()

Returns a string representation of the subnet like "1.0.0.0/24" or
"a800:f000::/105".

=head2 $subnet->version()

Returns a 4 or 6 to indicate whether this is an IPv4 or IPv6 subnet.

=head2 $subnet->netmask()

Returns the numeric subnet as passed to the constructor.

=head2 $subnet->mask_length()

Returns the mask length for the subnet, which is either 32 (IPv4) or 128
(IPv6).

=head2 $subnet->max_netmask()

This returns the maximum possible numeric subnet that this subnet could fit
in. In other words, the 1.1.1.0/32 subnet could be part of the 1.1.1.0/24
subnet, so this returns 24.

=head2 $subnet->first()

Returns the first IP in the subnet as an L<MM::Net::IPAddress> object.

=head2 $subnet->last()

Returns the last IP in the subnet as an L<MM::Net::IPAddress> object.

=head2 $subnet->iterator()

This returns an anonymous sub that returns one IP address in the range each
time it's called.

For single address subnets (/32 or /128), this returns a single address.

When it has exhausted all the addresses in the subnet, it returns C<undef>

=head2 MM::Net::Subnet->range_as_subnets( $first, $last )

Given two IP addresses as strings, this method breaks the range up into the
largest subnets that include all the IP addresses in the range (including the
two passed to this method).

It also excludes any reserved subnets in the range (such as the 10.0.0.0/8 or
169.254.0.0/16 ranges).

This method works with both IPv4 and IPv6 addresses. If either address
contains a colon (:) then it assumes that you want IPv6 subnets.

=head1 SUPPORT

Please report any bugs or feature requests to C<bug-net-sweet@rt.cpan.org>, or
through the web interface at L<http://rt.cpan.org>. I will be notified, and
then you'll automatically be notified of progress on your bug as I make
changes.
