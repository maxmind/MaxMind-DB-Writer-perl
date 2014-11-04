use strict;
use warnings;
use utf8;

use lib 't/lib';

use Test::More;

use File::Temp qw( tempdir );
use Math::Int128 qw( uint128 );
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

{
    my $cb = sub {
        my $key = $_[0];
        $key =~ s/X$//;
        return $key eq 'array' ? [ 'array', 'uint32' ] : $key;
    };

    my $tree1 = MaxMind::DB::Writer::Tree->new(
        ip_version              => 6,
        record_size             => 24,
        database_type           => 'Test',
        languages               => ['en'],
        description             => { en => 'Test tree' },
        merge_record_collisions => 1,
        map_key_type_callback   => $cb,
    );

    my $count       = 2**12;
    my $ipv6_offset = uint128(2)**34;

    for my $i ( 1 .. $count ) {
        my $ipv4 = Net::Works::Network->new_from_integer(
            integer       => $i,
            prefix_length => 128,
            version       => 6
        );
        $tree1->insert_network( $ipv4, _data_record( $i % 16 ) );

        my $ipv6 = Net::Works::Network->new_from_integer(
            integer       => $i + $ipv6_offset,
            prefix_length => 128,
            version       => 6
        );
        $tree1->insert_network( $ipv6, _data_record( $i % 16 ) );
    }

    my $dir = tempdir( CLEANUP => 1 );
    my $file = "$dir/frozen-tree";
    $tree1->freeze_tree($file);

    my $tree2 = MaxMind::DB::Writer::Tree->new_from_frozen_tree(
        filename              => $file,
        map_key_type_callback => $cb,
    );

    my $tree1_output;
    open my $fh, '>', \$tree1_output;
    $tree1->write_tree($fh);
    close $fh;

    my $tree2_output;
    open $fh, '>', \$tree2_output;
    $tree2->write_tree($fh);
    close $fh;

    is(
        $tree1_output,
        $tree2_output,
        'output for tree is the same after freeze/thaw'
    );
}

done_testing();

sub _data_record {
    my $i = shift;

    return {
        utf8_string => 'unicode! ☯ - ♫ - ' . $i,
        double      => 42.123456 + $i,
        bytes       => pack( 'N', 42 + $i ),
        uint16      => 100 + $i,
        uint32      => 2**28 + $i,
        int32       => -1 * ( 2**28 + $i ),
        uint64      => ( uint128(1) << 60 ) + $i,
        uint128     => ( uint128(1) << 120 ) + $i,
        array       => [ 1, 2, 3, $i ],
        map         => {
            mapX => {
                utf8_stringX => 'hello - ' . $i,
                arrayX       => [ 7, 8, 9, $i ],
            },
        },
        boolean => $i % 2,
        float   => 1.1 + $i,
    };
}
