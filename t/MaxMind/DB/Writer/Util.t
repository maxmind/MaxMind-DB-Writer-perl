use strict;
use warnings;

use MaxMind::DB::Writer::Util qw( key_for_data );
use Test::More;

{ # Test that refcount does not affect the key. (It did previously.)
    my $array1 = [ 0, 0 ];
    my @array2 = ( 0, 0 );

    is(
        key_for_data($array1),
        key_for_data(\@array2),
        'two generations of structure generate same key'
    );

}

done_testing();
