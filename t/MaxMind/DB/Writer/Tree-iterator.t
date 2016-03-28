use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::DB::Writer
    qw( make_tree_from_pairs ranges_to_data test_iterator_sanity );
use Test::MaxMind::DB::Writer::Iterator;
use Test::More;

my ( $insert, $expect ) = ranges_to_data(
    [
        [ '1.1.1.1', '1.1.1.32' ],
    ],
    [
        [ '1.1.1.1', '1.1.1.32' ],
    ],
);

my $basic_tree = make_tree_from_pairs('network', $insert);

{
    like(
        exception { $basic_tree->iterate( [] ) },
        qr/\QThe argument passed to iterate (ARRAY(\E.+\Q)) is not an object or class name/,
        'calling iterate() with a non object reference fails'
    );

    {
        package Foo;
    }
    like(
        exception { $basic_tree->iterate( bless {}, 'Foo' ) },
        qr/\QThe object or class passed to iterate must implement at least one method of process_empty_record, process_node_record, or process_data_record/,
        'calling iterate() with a method-less object fails'
    );
    like(
        exception { $basic_tree->iterate('Foo') },
        qr/\QThe object or class passed to iterate must implement at least one method of process_empty_record, process_node_record, or process_data_record/,
        'calling iterate() with a method-less class fails'
    );

    {
        package Bar;
        sub process_empty_record { }
    }
    is(
        exception { $basic_tree->iterate( bless {}, 'Bar' ) },
        undef,
        'calling iterate() with an object with only a process_empty_record method succeeds'
    );

    is(
        exception { $basic_tree->iterate('Bar') },
        undef,
        'calling iterate() with a class with process_empty_record method succeeds'
    );
}

{
    my $iterator = Test::MaxMind::DB::Writer::Iterator->new(4);
    $basic_tree->iterate($iterator);

    test_iterator_sanity( $iterator, $basic_tree, 6, 'basic tree' );

    is_deeply(
        [
            sort { $a->{id} <=> $b->{id} }
            map  { $_->[1] } @{ $iterator->{data_records} }
        ],
        [ sort { $a->{id} <=> $b->{id} } map { $_->[1] } @{$expect} ],
        'saw expected data records - basic tree'
    );

    my @data_record_networks = qw(
        1.1.1.1/32
        1.1.1.2/31
        1.1.1.4/30
        1.1.1.8/29
        1.1.1.16/28
        1.1.1.32/32
    );

    is_deeply(
        [ sort map { "$_->[0]" } @{ $iterator->{data_records} } ],
        [ sort @data_record_networks ],
        'saw the expected networks for data records - basic tree'
    );
}

{
    my $tree = make_tree_from_pairs(
        'network',
        [
            map {
                [ Net::Works::Network->new_from_string( string => $_ ) =>
                        { foo => 42 } ]
            } qw( ::1.0.0.0/120 2003::/96 abcd::1000/116 )
        ],
        { alias_ipv6_to_ipv4 => 1 },
    );

    $tree->_create_ipv4_aliases();

    my $iterator = Test::MaxMind::DB::Writer::Iterator->new(6);
    $tree->iterate($iterator);

    test_iterator_sanity( $iterator, $tree, 3, 'aliased tree' );

    my @data_record_networks = qw(
        ::1.0.0.0/120
        2003::/96
        abcd::1000/116
    );

    is_deeply(
        [ sort map { "$_->[0]" } @{ $iterator->{data_records} } ],
        [ sort @data_record_networks ],
        'saw the expected networks for data records - aliased tree'
    );
}

done_testing();
