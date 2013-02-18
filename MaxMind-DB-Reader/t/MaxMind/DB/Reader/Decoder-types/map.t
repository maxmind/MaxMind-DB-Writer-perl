use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Reader::Decoder qw( test_decoding_of_type );
use Test::More;

test_decoding_of_type( map => test_cases_for('map') );

done_testing();
