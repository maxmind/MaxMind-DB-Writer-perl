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

my $tree = make_tree_from_pairs($insert);

{
    like(
        exception { $tree->iterate( [] ) },
        qr/\QThe argument passed to iterate (ARRAY(\E.+\Q)) is not an object or class name/,
        'calling iterate() with a non object reference fails'
    );

    {
        package Foo;
    }
    like(
        exception { $tree->iterate( bless {}, 'Foo' ) },
        qr/\QThe object or class passed to iterate must implement at least one method of process_empty_record, process_node_record, or process_data_record/,
        'calling iterate() with a method-less object fails'
    );
    like(
        exception { $tree->iterate('Foo') },
        qr/\QThe object or class passed to iterate must implement at least one method of process_empty_record, process_node_record, or process_data_record/,
        'calling iterate() with a method-less class fails'
    );

    {
        package Bar;
        sub process_empty_record { }
    }
    is(
        exception { $tree->iterate(  bless {}, 'Bar' ) },
       undef,
        'calling iterate() with an object with only a process_empty_record method succeeds'
    );

    is(
        exception { $tree->iterate('Bar') },
        undef,
        'calling iterate() with a class with process_empty_record method succeeds'
    );
}

{
    package TreeIterator;

    sub new {
        bless {}, shift;
    }

    sub process_node_record {
        my $self            = shift;
        my $node_num        = shift;
        my $dir             = shift;
        my $current_ip_num  = shift;
        my $current_netmask = shift;
        my $next_ip_num     = shift;
        my $next_netmask    = shift;
        my $next_node_num   = shift;

        $self->_saw_record( $node_num, $dir );

        return;
    }

    sub process_empty_record {
        my $self            = shift;
        my $node_num        = shift;
        my $dir             = shift;
        my $current_ip_num  = shift;
        my $current_netmask = shift;
        my $next_ip_num     = shift;
        my $next_netmask    = shift;

        $self->_saw_record( $node_num, $dir );

        return;
    }

    sub process_data_record {
        my $self            = shift;
        my $node_num        = shift;
        my $dir             = shift;
        my $current_ip_num  = shift;
        my $current_netmask = shift;
        my $next_ip_num     = shift;
        my $next_netmask    = shift;
        my $value           = shift;

        $self->_saw_record( $node_num, $dir );

        push @{ $self->{values} }, $value;

        return;
    }

    sub _saw_record {
        my $self     = shift;
        my $node_num = shift;
        my $dir      = shift;

        $self->{records}{"$node_num-$dir"}++;

        return;
    }
}

{
    my $iterator = TreeIterator->new();
    $tree->iterate($iterator);

    ok(
        ( all { $_ == 1 } values %{ $iterator->{nodes} } ),
        'each node was visited exactly once'
    );

    ok(
        ( all { $_ == 1 } values %{ $iterator->{records} } ),
        'each record was visited exactly once'
    );

    is(
        scalar values %{ $iterator->{records} },
        $tree->node_count() * 2,
        'saw every record for every node in the tree'
    );

    is_deeply(
        [ sort { $a->{id} <=> $b->{id} } @{ $iterator->{values} } ],
        [
            sort { $a->{id} <=> $b->{id} } map { $_->[1] } @{$expect}
        ],
        'saw expected values for records'
    );
}

done_testing();
