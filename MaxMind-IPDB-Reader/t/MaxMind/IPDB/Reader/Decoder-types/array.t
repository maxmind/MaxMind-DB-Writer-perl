use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Reader::Decoder qw( test_decoding_of_type );
use Test::More;

test_decoding_of_type( array => test_cases_for('array') );

done_testing();
