use strict;
use warnings;
use autodie;

use lib 't/lib';

use Test::Requires {
    JSON => 0,
};

use Test::MaxMind::DB::Writer qw( make_tree_from_pairs test_iterator_sanity );
use Test::MaxMind::DB::Writer::Iterator;
use Test::More;

use MaxMind::DB::Writer::Tree;

{
    open my $fh, '<', 't/test-data/geolite2-sample.json';
    my $geolite2_data = do { local $/; <$fh> };
    my $records = JSON->new->decode($geolite2_data);
    close $fh;

    my $tree = make_tree_from_pairs( $records, { alias_ipv6_to_ipv4 => 1 } );

    my $iterator = Test::MaxMind::DB::Writer::Iterator->new(6);
    $tree->iterate($iterator);

    test_iterator_sanity(
        $iterator, $tree, 1115,
        'tree from geolite2 sample data'
    );
}

done_testing();
