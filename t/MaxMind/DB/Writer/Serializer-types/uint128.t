use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Writer::Serializer qw( test_encoding_of_type );
use Test::More;

test_encoding_of_type( uint128 => test_cases_for('uint128') );

done_testing();
