use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 4,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        map_key_type_callback => sub { },
    );

    my $expected
        = qr{You cannot insert an IPv6 address [(]::(?:0[.]0[.]0[.])?2[)] into an IPv4 tree.};

    like(
        exception { $tree->insert_network( '::2/128', 'foo' ) },
        $expected,
        q{Cannot insert an IPv6 network into an IPv4 tree}
    );

    like(
        exception { $tree->insert_range( '::2', '::3', 'foo' ) },
        $expected,
        q{Cannot insert an IPv6 range into an IPv4 tree}
    );
}

done_testing();
