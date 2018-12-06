use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::DB::Writer qw(
    insert_for_type
    make_tree_from_pairs
    ranges_to_data
    test_tree
);
use Test::MaxMind::DB::Writer::Iterator ();
use Test::Fatal;
use Test::More;
use Test::Warnings qw( :all );

use MaxMind::DB::Writer::Tree ();

use Net::Works::Address ();
use Net::Works::Network ();

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

        # We're trying to insert into reserved space, which fails unless we
        # turn off this option since it is reserved!
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

        # We're trying to insert into reserved space, which fails unless we
        # turn off this option since it is reserved!
        { remove_reserved_networks => 0 },
    );
}

subtest '::/0 insertion' => sub {
    my $data = { ip => '::' };

    my $tree = make_tree_from_pairs(
        'network', [ [ '::/0' => $data ] ],

        # ::/0 contains networks we add as FIXED_EMPTY when this option is on.
        # As a result, we hit the branch where we silently ignore the insert
        # (current_bit > network->prefix_length in
        # insert_record_into_next_node()). This means we create the tree but
        # the insert was ignored, causing the lookup we're trying to test to
        # fail. So we turn off adding the FIXED_EMPTY networks to let this test
        # pass.
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
        exception { $tree->insert_network( '2002::/16', {} ) },
        qr/Attempted to overwrite an aliased network/,
        'Received exception when inserting an aliased network'
    );

    $tree->insert_network( '2002::/12', {} );
    is_deeply(
        $tree->lookup_ip_address('2002::1'),
        undef,
        'Insert containing aliased network is silently ignored in the aliased part',
    );
    is_deeply(
        $tree->lookup_ip_address('2000::1'),
        {},
        'Insert containing aliased network succeeds outside the aliased part',
    );

    like(
        exception { $tree->insert_network( '2002:0101:0101:0101::/64', {} ) },
        qr/Attempted to insert into an aliased network/,
        'Received exception when inserting into alias'
    );

    $tree->insert_network( '192.168.0.0/16', { a => 'b' } );
    is_deeply(
        $tree->lookup_ip_address('192.168.0.1'),
        undef,
        'Insert trying to overwrite reserved network set fixed empty is silently ignored',
    );

    $tree->insert_network( '192.0.0.0/8', { a => 'b' } );
    is_deeply(
        $tree->lookup_ip_address('192.168.10.1'),
        undef,
        'Insert containing reserved network set fixed empty is silently ignored in the reserved part',
    );
    is_deeply(
        $tree->lookup_ip_address('192.1.10.1'),
        { a => 'b' },
        'Insert containing reserved network set fixed empty succeeds outside the reserved part',
    );

    $tree->insert_network( '192.168.10.0/24', { a => 'b' } );
    is_deeply(
        $tree->lookup_ip_address('192.168.10.1'),
        undef,
        'Insert into reserved network set fixed empty is silently ignored',
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
        alias_ipv6_to_ipv4 => 0,

        # We can't insert ::/1 since it is reserved if we have this option to
        # remove the reserved networks on.
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

subtest 'Setting data on a fixed node' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'none',
        map_key_type_callback => sub { 'utf8_string' },

        # ::/96 gets added as a fixed node when we use `alias_ipv6_to_ipv4'
        alias_ipv6_to_ipv4 => 1,

        # This is irrelevant to this test.
        remove_reserved_networks => 0,
    );

    my $ip   = '::/96';
    my $data = { hi => 'there' };
    $tree->insert_network( $ip, $data );

    my $iterator = Test::MaxMind::DB::Writer::Iterator->new(6);
    $tree->iterate($iterator);

    is_deeply(
        [
            map { [ $_->[0]->as_string, $_->[1] ] }
                @{ $iterator->{data_records} }
        ],
        [

            # This is a little odd but I think makes sense because we refuse to
            # touch the fixed node. Its left record (::/97) and right record
            # (::128.0.0.0/97 AKA ::8000:0/97) point to the data.
            [ '::0/97',         $data ],
            [ '::128.0.0.0/97', $data ],
        ],
        'saw expected data records',
    );

    my @ips_in_tree = (
        '::0.0.0.0',
        '::0.0.0.1',
        '::128.0.0.0',
        '::128.0.0.1',
    );
    for my $i (@ips_in_tree) {
        is_deeply( $tree->lookup_ip_address($i), $data, "$i is in tree" );
    }

    my @ips_not_in_tree = (
        '8000::1',
    );
    for my $i (@ips_not_in_tree) {
        is_deeply( $tree->lookup_ip_address($i), undef, "$i is not in tree" );
    }
};

subtest 'Setting data on non-fixed node' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'none',
        map_key_type_callback => sub { 'utf8_string' },

        # Not relevant.
        alias_ipv6_to_ipv4 => 0,

        # This is irrelevant to this test.
        remove_reserved_networks => 0,
    );

    is_deeply(
        $tree->lookup_ip_address('8000::1'),
        undef,
        '8000::1 is not in tree',
    );

    my $data0 = { hi    => 'there' };
    my $data1 = { hello => 'there' };

    $tree->insert_network( '8000::/2', $data0 );
    $tree->insert_network( 'C000::/2', $data1 );

    my $iterator = Test::MaxMind::DB::Writer::Iterator->new(6);
    $tree->iterate($iterator);

    is_deeply(
        [
            map { [ $_->[0]->as_string, $_->[1] ] }
                @{ $iterator->{data_records} }
        ],
        [
            [ '8000::/2', $data0 ],
            [ 'c000::/2', $data1 ],
        ],
        'saw expected data records',
    );

    is_deeply(
        $tree->lookup_ip_address('8000::1'),
        $data0,
        '8000::1 is in tree',
    );
};

subtest 'Removing regular networks' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'none',
        map_key_type_callback => sub { 'utf8_string' },

        # Having these off starts us with a very empty tree
        alias_ipv6_to_ipv4       => 0,
        remove_reserved_networks => 0,
    );

    like(
        exception { _node_is_in_tree( $tree, '8000::/1' ) },
        qr/Iteration is not currently allowed in trees with no nodes/,
        'no nodes in the tree',
    );

    my $data = { hi => 'there' };

    $tree->insert_network( 'aaaa::/64', $data );

    is_deeply(
        $tree->lookup_ip_address('aaaa::1'),
        $data,
        'record is in tree',
    );

    ok( _node_is_in_tree( $tree, '8000::/1' ), '8000::/1 is in the tree' );

    $tree->remove_network('::/0');

    is_deeply(
        $tree->lookup_ip_address('aaaa::1'),
        undef,
        'record is no longer in tree',
    );

    # After removing it, trimming removes all the way up.

    like(
        exception { _node_is_in_tree( $tree, '8000::/1' ) },
        qr/Iteration is not currently allowed in trees with no nodes/,
        'no nodes in the tree',
    );
};

subtest 'Removing fixed node' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'none',
        map_key_type_callback => sub { 'utf8_string' },
        alias_ipv6_to_ipv4    => 1,
    );

    # We have lots of fixed nodes because of both alias_ipv6_to_ipv4 and
    # because of the fixed emptys from remove_reserved_networks.

    ok( _node_is_in_tree( $tree, '8000::/1' ), '8000::/1 is in the tree' );

    $tree->remove_network('::/0');

    ok( _node_is_in_tree( $tree, '8000::/1' ), '8000::/1 is in the tree' );
};

subtest 'Inserting beside fixed empty record' => sub {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        merge_strategy        => 'none',
        map_key_type_callback => sub { 'utf8_string' },
    );

    my $data = { hi => 'there' };

    # ff00::/8 is a fixed empty

    # Left of it

    is_deeply(
        $tree->lookup_ip_address('fe00::1'),
        undef,
        'fe00::1 is not in tree',
    );

    $tree->insert_network( 'fe00::/8', $data );

    is_deeply(
        $tree->lookup_ip_address('fe00::1'),
        $data,
        'fe00::1 is in tree',
    );

    # 100::/64 is a fixed empty

    # Right of it

    is_deeply(
        $tree->lookup_ip_address('100:0:0:1::1'),
        undef,
        '100:0:0:1::1 is not in tree',
    );

    $tree->insert_network( '100:0:0:1::/64', $data );

    is_deeply(
        $tree->lookup_ip_address('100:0:0:1::1'),
        $data,
        '100:0:0:1::1 is in tree',
    );

    # Above and right of it

    is_deeply(
        $tree->lookup_ip_address('100:0:0:2::1'),
        undef,
        '100:0:0:2::1 is not in tree',
    );

    $tree->insert_network( '100:0:0:2::/63', $data );

    is_deeply(
        $tree->lookup_ip_address('100:0:0:2::1'),
        $data,
        '100:0:0:2::1 is in tree',
    );

    # 2001:db8::/32 is a fixed empty

    # Above and left of it

    is_deeply(
        $tree->lookup_ip_address('2001:db7::1'),
        undef,
        '2001:db7::1 is not in tree',
    );

    $tree->insert_network( '2001:db7::/31', $data );

    is_deeply(
        $tree->lookup_ip_address('2001:db7::1'),
        $data,
        '2001:db7::1 is in tree',
    );
};

done_testing();

sub _node_is_in_tree {
    my $tree    = shift;
    my $network = shift;

    my $iterator = Test::MaxMind::DB::Writer::Iterator->new(6);
    $tree->iterate($iterator);

    my @recs
        = grep { $_->as_string eq $network } @{ $iterator->{node_records} };

    return @recs > 0;
}

sub _test_subnet_permutations {
    my $subnets = shift;
    my $desc    = shift;

    my $id     = 0;
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

        # We happen to insert into reserved networks here and in the tests that
        # call us, so don't prevent that.
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
