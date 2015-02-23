use strict;
use warnings;

use Devel::Refcount qw( refcount );
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;
use Test::More;

subtest 'Reference counting when replacing node, no merging' => sub {
    _test_insert();
};

subtest 'Reference counting with merging' => sub {
    _test_insert( merge_record_collisions => 1 );
};

sub _test_insert {
    my %extra_tree_args = @_;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test' },
        map_key_type_callback => sub { },
        %extra_tree_args,
    );

    my $network = Net::Works::Network->new_from_string(
        string  => '8.23.0.0/16',
        version => 6
    );

    my $data = { test => 1 };

    $tree->insert_network(
        $network,
        $data,
    );
    is(
        Devel::Refcount::refcount($data), 2,
        'ref count of 2 after initial insert'
    );

    $tree->insert_network(
        $network,
        { blah => 2 },
    );

    is(
        Devel::Refcount::refcount($data), 1,
        'ref count of 1 after data is overwritten'
    );
};

done_testing();
