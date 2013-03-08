use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::DB::Writer::Tree::InMemory;
use Net::Works::Network;

my $ipv4_subnet
    = Net::Works::Network->new_from_string( string => '1.1.1.0/24' );
my $ipv6_subnet = Net::Works::Network->new_from_string( string => '::2/128' );

{
    my $tree = MaxMind::DB::Writer::Tree::InMemory->new();

    $tree->insert_subnet( $ipv4_subnet, 'foo' );
    like(
        exception { $tree->insert_subnet( $ipv6_subnet, 'foo' ) },
        qr{\QYou cannot insert an IPv6 subnet (::2/128) into an IPv4 tree.},
        q{Cannot insert an IPv6 subnet after we've already inserted an IPv4 subnet}
    );
}

{
    my $tree = MaxMind::DB::Writer::Tree::InMemory->new();

    $tree->insert_subnet( $ipv6_subnet, 'foo' );
    like(
        exception { $tree->insert_subnet( $ipv4_subnet, 'foo' ) },
        qr{\QYou cannot insert an IPv4 subnet (1.1.1.0/24) into an IPv6 tree.},
        q{Cannot insert an IPv4 subnet after we've already inserted an IPv6 subnet}
    );
}

done_testing();
