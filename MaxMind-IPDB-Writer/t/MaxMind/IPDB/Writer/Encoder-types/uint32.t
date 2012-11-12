use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Encoder qw( test_encoding_of_type );
use Test::More;

test_encoding_of_type( uint32 => test_cases_for('uint32') );

{
    my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => \*STDOUT );

    like(
        exception { $encoder->encode_uint32(undef) },
        qr/\QYou cannot encode undef as a unsigned 32-bit integer./,
        q{cannot encode undef as an unsigned integer}
    );

    like(
        exception { $encoder->encode_uint32('foo') },
        qr/\QYou cannot encode foo as a unsigned 32-bit integer. It is not an unsigned integer number/,
        q{cannot encode "foo" as an unsigned integer}
    );

    like(
        exception { $encoder->encode_uint32(-1) },
        qr/\QYou cannot encode -1 as a unsigned 32-bit integer. It is not an unsigned integer number./,
        'cannot encode -1 as an unsigned integer'
    );

    like(
        exception { $encoder->encode_uint32( 2**33 ) },
        qr/\QYou cannot encode \E\d+\Q as a unsigned 32-bit integer. It is too big./,
        'cannot encode 2**33 as an unsigned 32-bit integer'
    );
}

done_testing();
