use strict;
use warnings;

use Test::More;

use MaxMind::DB::Common
    qw( LEFT_RECORD RIGHT_RECORD DATA_SECTION_SEPARATOR_SIZE );

is( LEFT_RECORD,                 0,  'LEFT_RECORD' );
is( RIGHT_RECORD,                1,  'RIGHT_RECORD' );
is( DATA_SECTION_SEPARATOR_SIZE, 16, 'DATA_SECTION_SEPARATOR_SIZE' );

done_testing();
