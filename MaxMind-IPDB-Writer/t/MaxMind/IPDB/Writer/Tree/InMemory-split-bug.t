use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::IPDB::Writer::Tree::InMemory;

use Net::Works::Network;
use Socket qw( inet_ntoa );

{
    my $tree = MaxMind::IPDB::Writer::Tree::InMemory->new();

    no warnings 'redefine';
    local *MaxMind::IPDB::Writer::Tree::InMemory::_split_node
        = sub { die 'called _split_node' };

    is(
        exception {
            for my $i ( 0 .. 2**16 ) {
                my $subnet
                    = Net::Works::Network->new_from_integer( subnet => $i,
                    mask_length => 32 );

                $tree->insert_subnet( $subnet, 0 );
            }
        },
        undef,
        ' no calls to _split_node when inserting 2**32 subnets '
    );
}

done_testing();
