use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Encoder qw( test_encoding_of_type );
use Test::More;

test_encoding_of_type( int32 => test_cases_for('int32') );

done_testing();
