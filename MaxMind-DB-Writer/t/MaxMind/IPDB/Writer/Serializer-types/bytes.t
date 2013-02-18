use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Serializer qw( test_encoding_of_type );
use Test::More;

test_encoding_of_type( bytes => test_cases_for('bytes') );

done_testing();
