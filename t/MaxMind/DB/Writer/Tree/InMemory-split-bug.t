use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::DB::Writer::Tree::InMemory;

use Net::Works::Network;

{
    my $tree = MaxMind::DB::Writer::Tree::InMemory->new( ip_version => 4 );

    no warnings 'redefine';
    local *MaxMind::DB::Writer::Tree::InMemory::_split_node
        = sub { die 'called _split_node' };

    is(
        exception {
            for my $i ( 0 .. 2**16 ) {
                my $subnet = Net::Works::Network->new_from_integer(
                    integer     => $i,
                    mask_length => 32,
                );

                $tree->insert_subnet( $subnet, 0 );
            }
        },
        undef,
        'no calls to _split_node when inserting 2**32 subnets'
    );
}

done_testing();
