use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::DB::Writer qw( make_tree_from_pairs ranges_to_data );
use Test::More;

use List::Util qw( all );
use MaxMind::DB::Writer::Tree;

my ( $insert, $expect ) = ranges_to_data(
    [
        [ '1.1.1.1', '1.1.1.32' ],
    ],
    [
        [ '1.1.1.1', '1.1.1.32' ],
    ],
);

my $basic_tree = make_tree_from_pairs($insert);

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
    package TreeIterator;

    sub new {
        my $class      = shift;
        my $ip_version = shift;

        return bless { ip_version => $ip_version }, $class;
    }

    sub process_node_record {
        my $self               = shift;
        my $node_num           = shift;
        my $dir                = shift;
        my $node_ip_num        = shift;
        my $node_mask_length   = shift;
        my $record_ip_num      = shift;
        my $record_mask_length = shift;
        my $record_node_num    = shift;

        $self->_saw_network( $node_ip_num, $node_mask_length, 'node' );

        $self->_saw_record( $node_num, $dir );

        return;
    }

    sub process_empty_record {
        my $self               = shift;
        my $node_num           = shift;
        my $dir                = shift;
        my $node_ip_num        = shift;
        my $node_mask_length   = shift;
        my $record_ip_num      = shift;
        my $record_mask_length = shift;

        $self->_saw_network( $node_ip_num, $node_mask_length, 'empty' );

        $self->_saw_record( $node_num, $dir );

        return;
    }

    sub process_data_record {
        my $self               = shift;
        my $node_num           = shift;
        my $dir                = shift;
        my $node_ip_num        = shift;
        my $node_mask_length   = shift;
        my $record_ip_num      = shift;
        my $record_mask_length = shift;
        my $value              = shift;

        $self->_saw_network( $node_ip_num, $node_mask_length, 'data' );

        $self->_saw_record( $node_num, $dir );

        push @{ $self->{data_records} },
            [
            $self->_nw_network( $record_ip_num, $record_mask_length ),
            $value,
            ];

        return;
    }

    sub _saw_network {
        my $self        = shift;
        my $ip_num      = shift;
        my $mask_length = shift;
        my $type        = shift;

        my $network = $self->_nw_network( $ip_num, $mask_length );

        $self->{networks}{ $network->as_string() }++;
    }

    sub _saw_record {
        my $self     = shift;
        my $node_num = shift;
        my $dir      = shift;

        $self->{records}{"$node_num-$dir"}++;

        return;
    }

    sub _nw_network {
        my $self        = shift;
        my $ip_num      = shift;
        my $mask_length = shift;

        return Net::Works::Network->new_from_integer(
            integer     => $ip_num,
            mask_length => $mask_length,
            version     => $self->{ip_version},
        );
    }
}

{
    my $iterator = TreeIterator->new(4);
    $basic_tree->iterate($iterator);

    _test_iterator_sanity( $iterator, $basic_tree, 'basic tree' );

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
        [
            map {
                [ Net::Works::Network->new_from_string( string => $_ ) =>
                        { foo => 42 } ]
            } qw( ::1.0.0.0/120 2003::/96 abcd::1000/116 )
        ],
        { alias_ipv6_to_ipv4 => 1 },
    );

    $tree->_create_ipv4_aliases();

    my $iterator = TreeIterator->new(6);
    $tree->iterate($iterator);

    _test_iterator_sanity( $iterator, $tree, 'aliased tree' );

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

sub _test_iterator_sanity {
    my $iterator = shift;
    my $tree     = shift;
    my $desc     = shift;

    ok(
        ( all { $_ == 1 } values %{ $iterator->{nodes} } ),
        "each node was visited exactly once - $desc"
    );

    ok(
        ( all { $_ == 1 } values %{ $iterator->{records} } ),
        "each record was visited exactly once - $desc"
    );

    ok(
        ( all { $_ == 2 } values %{ $iterator->{networks} } ),
        "each network was visited exactly twice (two records per node) - $desc"
    );

    is(
        scalar values %{ $iterator->{records} },
        $tree->node_count() * 2,
        "saw every record for every node in the tree - $desc"
    );
}
