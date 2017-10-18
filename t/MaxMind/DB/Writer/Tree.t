use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::DB::Writer qw(
    insert_for_type
    make_tree_from_pairs
    ranges_to_data
    test_tree
);
use Test::Fatal;
use Test::More;
use Test::Warnings qw( :all );

use MaxMind::DB::Writer::Tree;

use Net::Works::Address;
use Net::Works::Network;

{
    my @ipv4_subnets
        = Net::Works::Network->range_as_subnets( '1.1.1.1', '1.1.1.32' );

    _test_subnet_permutations( \@ipv4_subnets, 'IPv4' );
}

{
    my @ipv4_subnets = (
        Net::Works::Network->range_as_subnets( '1.1.1.1',  '1.1.1.32' ),
        Net::Works::Network->range_as_subnets( '16.1.1.1', '16.1.3.2' ),
    );

    _test_subnet_permutations( \@ipv4_subnets, 'IPv4 - two distinct ranges' );
}

{
    my @ipv6_subnets = Net::Works::Network->range_as_subnets(
        '::1:ffff:ffff',
        '::2:0000:0059'
    );

    _test_subnet_permutations( \@ipv6_subnets, 'IPv6' );
}

{
    my @ipv6_subnets = (
        Net::Works::Network->range_as_subnets(
            '::1:ffff:ffff',
            '::2:0000:0001'
        ),
        Net::Works::Network->range_as_subnets(
            '2002::abcd',
            '2002::abd4',
        )
    );

    _test_subnet_permutations( \@ipv6_subnets, 'IPv6 - two distinct ranges' );
}

{
    my ( $insert, $expect ) = ranges_to_data(
        [
            [ '1.1.1.0', '1.1.1.15' ],
            [ '1.1.1.1', '1.1.1.32' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.0' ],
            [ '1.1.1.1', '1.1.1.32' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'overlapping subnets - first is lower'
    );
}

{
    my ( $insert, $expect ) = ranges_to_data(
        [
            [ '1.1.1.0',  '1.1.1.15' ],
            [ '1.1.1.14', '1.1.1.32' ],
        ],
        [
            [ '1.1.1.0',  '1.1.1.13' ],
            [ '1.1.1.14', '1.1.1.32' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'overlapping subnets - overlap breaks up first subnet into smaller chunks'
    );
}

{
    my ( $insert, $expect ) = ranges_to_data(
        [
            [ '1.1.1.1', '1.1.1.32' ],
            [ '1.1.1.0', '1.1.1.15' ],
        ],
        [
            [ '1.1.1.0',  '1.1.1.15' ],
            [ '1.1.1.16', '1.1.1.32' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'overlapping subnets - first is higher'
    );
}

{
    my ( $insert, $expect ) = ranges_to_data(
        [
            [ '1.1.1.0', '1.1.1.15' ],
            [ '1.1.1.1', '1.1.1.14' ],
        ],
        [
            [ '1.1.1.0',  '1.1.1.0' ],
            [ '1.1.1.1',  '1.1.1.14' ],
            [ '1.1.1.15', '1.1.1.15' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'first subnet contains second subnet'
    );
}

{
    my ( $insert, $expect ) = ranges_to_data(
        [
            [ '1.1.1.1', '1.1.1.14' ],
            [ '1.1.1.0', '1.1.1.15' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.15' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'second subnet contains first subnet'
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '0.0.0.0/32' ),
            { ip => '0.0.0.0' }
        ]
    );

    test_tree(
        \@pairs,
        \@pairs,
        '0.0.0.0/32 network',
        { remove_reserved_networks => 0 },
    );
}

{
    my @pairs = (
        [
            Net::Works::Network->new_from_string( string => '::0.0.0.0/128' ),
            { ip => '0.0.0.0' }
        ]
    );

    test_tree(
        \@pairs,
        \@pairs,
        '::0.0.0.0/128 network',
        { remove_reserved_networks => 0 },
    );
}

subtest '::/0 insertion' => sub {
    my $data = { ip => '::' };

    my $tree = make_tree_from_pairs( 'network', [ [ '::/0' => $data ] ],
        { remove_reserved_networks => 0 },
    );

    is_deeply( $tree->lookup_ip_address('::'), $data, ':: is in tree' );
    is_deeply(
        $tree->lookup_ip_address('9000::'), $data,
        '9000:: is in tree'
    );
};

# Tests handling of inserting multiple networks that all have the same data -
# if we end up with a node that has two identical data records, we want to
# remove that node entirely and move the data record up to the parent.
subtest 'test merging nodes' => sub {
    my @distinct_subnets
        = Net::Works::Network->new_from_string( string => '128.0.0.0/1' )
        ->split;

    for my $type ( 'network', 'range' ) {
        for my $split_count ( 2 ... 8 ) {
            my $tree = _create_and_insert_duplicates(
                $type,
                $split_count,
                \@distinct_subnets
            );

            is(
                $tree->node_count(), 2,
                'duplicates merged for split count of ' . $split_count
            );

            for my $ip ( '0.1.2.3', '13.1.0.0', '126.255.255.255' ) {
                my $address
                    = Net::Works::Address->new_from_string( string => $ip );
                is(
                    $tree->lookup_ip_address($address), 'duplicate',
                    qq{$address data value is 'duplicate' for split count $split_count}
                );
            }

            for my $subnet (@distinct_subnets) {
                my $first = $subnet->first();
                my $value = $first->as_string();
                for my $address ( $first, $first->next_ip() ) {
                    is(
                        $tree->lookup_ip_address($address), $value,
                        qq{$address data value is $value for split count of $split_count}
                    );
                }
            }
        }
    }
};

subtest 'Inserting invalid networks and ranges' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'toplevel',
        map_key_type_callback => sub { 'utf8_string' },
        alias_ipv6_to_ipv4    => 1,
    );

    like(
        exception { $tree->insert_range( '2002::', '2001::', {} ) },
        qr/in range comes before last IP /, 'First IP after last IP in range'
    );

    like(
        exception { $tree->insert_range( '2001:', '2002:', {} ) },
        qr/Invalid IP/, 'invalid IP in range'
    );

    like(
        exception { $tree->insert_network( '2001:/129', {} ) },
        qr/Invalid network/, 'prefix length too large'
    );

    like(
        exception { $tree->insert_network( '2001:/-1', {} ) },
        qr/Invalid network/, 'negative prefix length'
    );

    like(
        exception { $tree->insert_network( '2001:/1', {} ) },
        qr/Invalid IP/, 'invalid IP in network'
    );

    like(
        exception { $tree->insert_network( '2002:0101:0101:0101::/64', {} ) },
        qr/Attempted to insert into an aliased network/,
        'Received exception when inserting into alias'
    );
};

subtest 'Recording merging at /0' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'toplevel',
        map_key_type_callback => sub { 'utf8_string' },

        # These are 0 to as enabling them will create more than one network
        alias_ipv6_to_ipv4       => 0,
        remove_reserved_networks => 0,
    );

    my $data = { data => 1 };
    $tree->insert_network( '::/1',     $data );
    $tree->insert_network( '8000::/1', $data );

    for my $ip ( '::', '2000::', '8000::', '9000::' ) {
        is_deeply(
            $tree->lookup_ip_address($ip), $data,
            "expected data for $ip"
        );
    }
};

done_testing();

sub _test_subnet_permutations {
    my $subnets = shift;
    my $desc    = shift;

    my $id = 0;
    my @expect = map { [ $_, { foo => 42, id => $id++ } ] } @{$subnets};

    {
        # In this case what we insert into the tree matches the order of what
        # we expect
        test_tree(
            \@expect, \@expect,
            "ordered subnets - $desc",
        );
    }

    {
        my @reversed = reverse @expect;

        test_tree(
            \@reversed, \@expect,
            "reversed subnets - $desc"
        );
    }

    {
        my @odd  = grep { $_ % 2 } 0 .. $#expect;
        my @even = grep { !( $_ % 2 ) } 0 .. $#expect;

        my @shuffled = ( @expect[@odd], @expect[ reverse @even ] );

        test_tree(
            \@shuffled, \@expect,
            "shuffled subnets - $desc"
        );
    }

    {
        my @duplicated = ( @expect, @expect );

        test_tree(
            \@duplicated, \@expect,
            "duplicated subnets - $desc"
        );
    }
}

sub _test_tree_as_ipv4_and_ipv6 {
    my $insert = shift;
    my $expect = shift;
    my $desc   = shift;

    test_tree( $insert, $expect, $desc );
    _test_tree_as_ipv6( $insert, $expect, $desc );
}

sub _test_tree_as_ipv6 {
    my $insert = shift;
    my $expect = shift;
    my $desc   = shift;

    $insert = [ map { [ _subnet_as_v6( $_->[0] ), $_->[1] ] } @{$insert} ];
    $expect = [ map { [ _subnet_as_v6( $_->[0] ), $_->[1] ] } @{$expect} ];

    test_tree( $insert, $expect, $desc . ' - IPv6' );
}

sub _subnet_as_v6 {
    my $subnet = shift;

    my $subnet_string
        = '::'
        . $subnet->first()->as_string() . '/'
        . ( $subnet->prefix_length() + 96 );

    return Net::Works::Network->new_from_string(
        string  => $subnet_string,
        version => 6,
    );
}

sub _create_and_insert_duplicates {
    my $type             = shift;
    my $split_count      = shift;
    my $distinct_subnets = shift;

    my $tree = make_tree_from_pairs(
        $type,
        [ map { [ $_, $_->as_string() ] } @{$distinct_subnets} ],
        { remove_reserved_networks => 0 },
    );

    my @duplicate_data_subnets
        = ( Net::Works::Network->new_from_string( string => '0.0.0.0/1' ) );

    @duplicate_data_subnets = map { $_->split() } @duplicate_data_subnets
        for ( 1 .. $split_count );

    for my $subnet (@duplicate_data_subnets) {
        insert_for_type( $tree, $type, $subnet, 'duplicate' );
    }

    for my $subnet (@$distinct_subnets) {
        insert_for_type( $tree, $type, $subnet, $subnet->first->as_string );
    }

    return $tree;
}
