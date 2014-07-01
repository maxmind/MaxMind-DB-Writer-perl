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
    my %asn = (
        autonomous_system_number       => 21928,
        autonomous_system_organization => 'T-Mobile USA, Inc.',
    );

    my $isp = 'T-Mobile ISP';
    my $org = 'T-Mobile Org';

    my @pairs = (
        [
            Net::Works::Network->new_from_string(
                string => '::172.56.0.0/112'
            ) => \%asn,
        ],
        [
            Net::Works::Network->new_from_string(
                string => '::172.56.0.0/112'
            ) => { isp => $isp },
        ],
        [
            Net::Works::Network->new_from_string(
                string => '::172.32.0.0/107'
            ) => { organization => $org, },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string(
                string => '::172.56.9.251/128'
            ) => { %asn, isp => $isp, organization => $org, }
        ],
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - ipv6',
        { merge_record_collisions => 1 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '5.0.0.0/32' ) =>
                { first_in => 1 },
        ],
        [
            Net::Works::Network->new_from_string( string => '5.0.0.0/30' ) =>
                { second_in => 2 },
        ],
        [
            Net::Works::Network->new_from_string( string => '5.0.0.0/32' ) =>
                { third_in => 3 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '5.0.0.0/32' ) =>
                { first_in => 1, second_in => 2, third_in => 3, }
        ],
        (
            map { [ $_ => { second_in => 2 } ] }
                Net::Works::Network->range_as_subnets(
                '5.0.0.1' => '5.0.0.3'
                )
        ),
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - small net, large net, small net',
        { merge_record_collisions => 1 },
    );
}
done_testing;
exit;
{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/30' ) =>
                { first_in => 1 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { second_in => 2 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/30' ) =>
                { third_in => 3 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1, second_in => 2, third_in => 3, }
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.1/32' ) =>
                { first_in => 1, third_in => 3, }
        ],
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - large net, small net, large net',
        { merge_record_collisions => 1 },
    );
}
done_testing;
exit;

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { second_in => 2 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1, second_in => 2, }
        ],
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - same network',
        { merge_record_collisions => 1 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/23' ) =>
                { first_in => 1 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/24' ) =>
                { second_in => 2 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1, second_in => 2, }
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.1.0/32' ) =>
                { first_in => 1, }
        ],
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - overlapping network, larger net first',
        { merge_record_collisions => 1 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/24' ) =>
                { first_in => 1 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/23' ) =>
                { second_in => 2 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1, second_in => 2, }
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.1.0/32' ) =>
                { second_in => 2, }
        ],
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - overlapping network, smaller net first',
        { merge_record_collisions => 1 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/31' ) =>
                { second_in => 2 },
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/30' ) =>
                { third_in => 3 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '2.0.0.0/32' ) =>
                { first_in => 1, second_in => 2, third_in => 3, }
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.1/32' ) =>
                { second_in => 2, third_in => 3, }
        ],
        [
            Net::Works::Network->new_from_string( string => '2.0.0.2/31' ) =>
                { third_in => 3, }
        ],
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - smaller nets first',
        { merge_record_collisions => 1 },
    );
}

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
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/16' ) =>
                { fourth_in => 4 },
        ],
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/16' ) =>
                { fifth_in => 5 },
        ],
    );

    my @expect = (
        [
            Net::Works::Network->new_from_string( string => '1.0.0.0/32' ) =>
                {
                first_in => 1, third_in => 3, fourth_in => 4,
                fifth_in => 5,
                }
        ],
        (
            map {
                [
                    $_ => {
                        first_in  => 1,
                        second_in => 2,
                        third_in  => 3,
                        fourth_in => 4,
                        fifth_in  => 5,
                    }
                ]
                } Net::Works::Network->range_as_subnets(
                '1.0.0.1' => '1.0.0.2'
                )
        ),
        (
            map {
                [
                    $_ => {
                        first_in  => 1,
                        third_in  => 3,
                        fourth_in => 4,
                        fifth_in  => 5,
                    }
                ]
                } Net::Works::Network->range_as_subnets(
                '1.0.0.3' => '1.0.0.4'
                )
        ),
        (
            map { [ $_ => { fourth_in => 4, fifth_in => 5, } ] }
                Net::Works::Network->range_as_subnets(
                '1.0.255.254' => '1.0.255.255'
                )
        ),
    );

    test_tree(
        \@pairs,
        \@expect,
        'data hashes for records are merged on collision - smaller net first',
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
