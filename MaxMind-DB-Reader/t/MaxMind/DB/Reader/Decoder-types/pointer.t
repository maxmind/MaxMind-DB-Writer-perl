use strict;
use warnings;

use lib 't/lib';

BEGIN { $ENV{MAXMIND_DB_POINTER_TEST_HACK} = 1 }

use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Reader::Decoder qw( test_decoding_of_type );
use Test::More;

test_decoding_of_type( pointer => test_cases_for('pointer') );

done_testing();
