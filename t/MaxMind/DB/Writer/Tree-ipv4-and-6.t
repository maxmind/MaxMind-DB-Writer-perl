use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

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

    like(
        exception { $tree->insert_network( $ipv6_network, 'foo' ) },
        qr{You cannot insert an IPv6 network [(]::(?:0[.]0[.]0[.])?2/128[)] into an IPv4 tree.},
        q{Cannot insert an IPv6 network into an IPv4 tree}
    );
}

done_testing();
