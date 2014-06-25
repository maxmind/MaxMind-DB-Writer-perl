use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::DB::Writer
    qw( make_tree_from_pairs ranges_to_data test_tree );
use Test::More;

use MaxMind::DB::Writer::Tree;

use Net::Works::Network;

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/24' ) =>
                { first_in => 1 },
        ],
        (
            map { [ $_ => { second_in => 2 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.2'
                )
        ),
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/24' ) =>
                { third_in => 3 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/32' ) =>
                { first_in => 1, third_in => 3 }
        ],
        (
            map { [ $_ => { first_in => 1, second_in => 2, third_in => 3 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.2'
                )
        ),
        (
            map { [ $_ => { first_in => 1, third_in => 3 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.3' => '1.0.0.4'
                )
        )
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - larger net first',
        { merge_record_collisions => 1 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/24' ) =>
                { foo => 42 },
        ],
        (
            map { [ $_ => { bar => 84 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.15'
                )
        ),
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/32' ) =>
                { foo => 42 }
        ],
        (
            map { [ $_ => { foo => 42, bar => 84 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.15'
                )
        ),
        (
            map { [ $_ => { foo => 42 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.16' => '1.0.0.255'
                )
        )
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - larger net first',
        { merge_record_collisions => 1 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/24' ) =>
                { foo => 42 },
        ],
        (
            map { [ $_ => { bar => 84 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.15'
                )
        ),
        (
            map { [ $_ => { baz => 168 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.9' => '1.0.0.13'
                )
        ),
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/32' ) =>
                { foo => 42 }
        ],
        (
            map { [ $_ => { foo => 42, bar => 84 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.8'
                )
        ),
        (
            map { [ $_ => { foo => 42, bar => 84, baz => 168 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.9' => '1.0.0.13'
                )
        ),
        (
            map { [ $_ => { foo => 42, bar => 84 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.14' => '1.0.0.15'
                )
        ),
        (
            map { [ $_ => { foo => 42 } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.0.16' => '1.0.0.255'
                )
        )
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on repeated collision - larger net first',
        { merge_record_collisions => 1 },
    );
}

{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version              => 4,
        record_size             => 24,
        database_type           => 'Test',
        languages               => ['en'],
        description             => { en => 'Test tree' },
        merge_record_collisions => 1,
    );

    $tree->insert_network(
        Net::Works::Network->new_from_string( string => '1.0.0.0/24' ),
        { hash => 1 },
    );

    for my $data ( 'foo', 42, [ array => 1 ] ) {
        like(
            exception {
                $tree->insert_network(
                    Net::Works::Network->new_from_string(
                        string => '1.0.0.0/28'
                    ),
                    $data,
                );
            },
            qr{\QCannot merge data records unless both records are hashes - inserting 1.0.0.0/28},
            "cannot merge records on collision when the data is not a hash - data = $data"
        );
    }
}

{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version              => 4,
        record_size             => 24,
        database_type           => 'Test',
        languages               => ['en'],
        description             => { en => 'Test tree' },
        merge_record_collisions => 1,
    );

    $tree->insert_network(
        Net::Works::Network->new_from_string( string => '1.0.0.0/24' ),
        [ array => 1 ],
    );

    like(
        exception {
            $tree->insert_network(
                Net::Works::Network->new_from_string(
                    string => '1.0.0.0/28'
                ),
                { hash => 1 },
            );
        },
        qr{\QCannot merge data records unless both records are hashes - inserting 1.0.0.0/28},
        "cannot merge records on collision when the data is not a hash - larger record data is an array"
    );
}

done_testing();
