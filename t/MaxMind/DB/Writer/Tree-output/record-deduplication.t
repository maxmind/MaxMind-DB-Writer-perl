use strict;
use warnings;
use autodie;

use lib 't/lib';

use File::Temp qw( tempdir );
use Test::MaxMind::DB::Writer qw( make_tree_from_pairs );
use Test::More;

use Net::Works::Network;

my $data1 = {
    map1 => {
        map2 => { int1 => 42 },
        map3 => { int2 => 84 },
    },
    array1 => [ 1, 2, 3 ],
};

my $data2 = {
    map1 => {
        map2 => { int1 => 43 },
        map3 => { int2 => 85 },
    },
    array1 => [ 4, 5, 6 ],
};

my $tree = make_tree_from_pairs(
    [
        [ '1.0.0.0/24' => $data1 ],
        [ '2.0.0.0/24' => $data1 ],
        [ '3.0.0.0/24' => $data2 ],
        [ '4.0.0.0/24' => $data2 ],
    ],
    {
        map_key_type_callback => sub {
            $_[0] =~ /^(\D+)/
                or die "No type for key = $_[0]";
            return
                  $1 eq 'array' ? [ 'array', 'uint32' ]
                : $1 eq 'int'   ? 'uint32'
                :                 $1;
        },
    },
);

my $dir = tempdir( CLEANUP => 1 );
open my $fh, '>', "$dir/dedupe.mmdb";

my $calls = 0;

{
    package MaxMind::DB::Writer::Serializer;
    no warnings 'redefine';
    my $sd = __PACKAGE__->can('store_data');
    *store_data = sub {
        my $self = shift;

        # We want to track calls to this method made from tree.c (not internal
        # recursive calls).
        if ( ( caller(0) )[0] ne __PACKAGE__ ) {

            # There's always one call to store the metadata
            $calls++
                unless $_[1]->{build_epoch};
        }

        return $self->$sd(@_);
    };
}

$tree->write_tree($fh);

is(
    $calls, 2,
    'store_data was only called twice because identical record values are deduplicated'
);

close $fh;

done_testing();
