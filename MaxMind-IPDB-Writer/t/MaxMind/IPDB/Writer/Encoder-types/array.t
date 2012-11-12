use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Encoder qw( test_encoding_of_type );
use Test::More;

use MaxMind::IPDB::Writer::Encoder;

test_encoding_of_type( array => test_cases_for('array') );

done_testing();
