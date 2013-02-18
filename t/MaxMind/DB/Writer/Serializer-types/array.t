use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Writer::Serializer qw( test_encoding_of_type );
use Test::More;

use MaxMind::DB::Writer::Serializer;

test_encoding_of_type( array => test_cases_for('array') );

done_testing();
