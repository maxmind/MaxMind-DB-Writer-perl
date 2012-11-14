use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Encoder qw( test_encoding_of_type );
use Test::More;

use MaxMind::IPDB::Writer::Encoder;

test_encoding_of_type( map => test_cases_for('map') );

{
    my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => \*STDOUT );

    like(
        exception { $encoder->_type_for_key('bad key') },
        qr/\QCould not determine the type for map key "bad key"/,
        'cannot guess the type for an unknown hash key'
    );
}

done_testing();
