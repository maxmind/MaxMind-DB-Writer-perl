use strict;
use warnings;

use Test::More;
use Test::MaxMind::DB::Common::Data;

my @subs = (
    '_array',   '_bytes',   '_double', '_float',  '_int32',  '_map',
    '_pointer', '_uint128', '_uint64', '_uint32', '_uint16', 'uint8',
    '_boolean'
);

foreach my $sub ( @subs ) {
    my $call = 'Test::MaxmMind::DB::Common::Data::' . $sub;
    ok( $call, $call );
}

done_testing();
