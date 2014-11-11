use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

my $ipv4_network
    = Net::Works::Network->new_from_string( string => '1.1.1.0/24' );
my $ipv6_network
    = Net::Works::Network->new_from_string( string => '::2/128' );

{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 4,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        map_key_type_callback => sub { },
    );

    $tree->insert_network( $ipv4_network, 'foo' );
    like(
        exception { $tree->insert_network( $ipv6_network, 'foo' ) },
        qr{\QYou cannot insert an IPv6 network (::2/128) into an IPv4 tree.},
        q{Cannot insert an IPv6 network after we've already inserted an IPv4 network}
    );
}

{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        map_key_type_callback => sub { },
    );

    $tree->insert_network( $ipv6_network, 'foo' );
    like(
        exception { $tree->insert_network( $ipv4_network, 'foo' ) },
        qr{\QYou cannot insert an IPv4 network (1.1.1.0/24) into an IPv6 tree.},
        q{Cannot insert an IPv4 network after we've already inserted an IPv6 network}
    );
}

done_testing();
