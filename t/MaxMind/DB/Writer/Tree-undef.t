use strict;
use warnings;

use Test::Fatal;
use Test::More 0.88;

use MaxMind::DB::Writer::Tree;
use Math::Int128 qw( uint128 );
use Net::Works::Network;

{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 4,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        map_key_type_callback =>  sub { 'utf8_string' },
    );

    is(
        exception {
            $tree->insert_network(
                Net::Works::Network->new_from_string(
                    string => '1.1.1.0/24'
                ),
                qr/\AYou cannot insert the undefined value into the tree/,
            );
        },
        undef,
        'testing',
    ) foreach (
        undef,
        \undef,
        [undef],
        {value => undef},
        { deep => [ \{ value => undef }] },
    );
}

done_testing();
