use strict;
use warnings;

use Test::Fatal;
use Test::More 0.88;

use MaxMind::DB::Writer::Tree;
use Math::Int128 qw( uint128 );
use Net::Works::Network;

{
    my $int128 = uint128(2) << 120;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 4,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        map_key_type_callback => sub { 'uint128' },
    );

    is(
        exception {
            $tree->insert_network(
                Net::Works::Network->new_from_string(
                    string => '1.1.1.0/24'
                ),
                { value => $int128 },
            );
        },
        undef,
        'no exception inserting data that includes a Math::UInt128 object'
    );

    my $record = $tree->lookup_ip_address(
        Net::Works::Address->new_from_string( string => '1.1.1.1' ) );

    is(
        $record->{value},
        $int128,
        'got expected value back with Math::UInt128 object'
    );
}

done_testing();
