use strict;
use warnings;

use Test::More;

use MaxMind::DB::Writer::Tree::InMemory;

use Net::Works::Network;

# The bug here occurs when we insert a subnet that wipes out an earlier
# subnet's data. This effectively wipes out a branch from the tree, so we need
# to account for that in the node count.

{
    my $tree = MaxMind::DB::Writer::Tree::InMemory->new( ip_version => 4 );

    for my $string (qw( 1.1.2.255/32 1.1.2.254/31 )) {
        my $subnet
            = Net::Works::Network->new_from_string( string => $string );

        $tree->insert_subnet( $subnet, { data => $string } );
    }

    is(
        $tree->node_count(),
        $tree->_real_node_count(),
        'node count maintained by tree as it goes matches node count of all visitable nodes'
    );
}

{
    my $tree = MaxMind::DB::Writer::Tree::InMemory->new( ip_version => 4 );

    for my $string (qw( 1.1.2.254/32 1.1.2.254/31 )) {
        my $subnet
            = Net::Works::Network->new_from_string( string => $string );

        $tree->insert_subnet( $subnet, { data => $string } );
    }

    is(
        $tree->node_count(),
        $tree->_real_node_count(),
        'node count maintained by tree as it goes matches node count of all visitable nodes'
    );
}

done_testing();
