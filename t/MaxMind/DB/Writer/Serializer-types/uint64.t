use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Writer::Serializer qw( test_encoding_of_type );
use Test::More;

use Math::Int128 qw( uint128 );
use MaxMind::DB::Writer::Serializer;

test_encoding_of_type( uint64 => test_cases_for('uint64') );

{
    my $serializer = MaxMind::DB::Writer::Serializer->new();

    like(
        exception { $serializer->_encode_uint64(undef) },
        qr/\QYou cannot encode undef as an unsigned 64-bit integer./,
        q{cannot encode undef as an unsigned integer}
    );

    like(
        exception { $serializer->_encode_uint64('foo') },
        qr/\QYou cannot encode foo as an unsigned 64-bit integer. It is not an unsigned integer number./,
        q{cannot encode "foo" as an unsigned integer}
    );

    like(
        exception { $serializer->_encode_uint64(-1) },
        qr/\QYou cannot encode -1 as an unsigned 64-bit integer. It is not an unsigned integer number./,
        'cannot encode -1 as an unsigned integer'
    );

    like(
        exception {
            $serializer->_encode_uint64( uint128('36893488147419103232') );
        },
        qr/\QYou cannot encode \E[\dA-F]+\Q as an unsigned 64-bit integer. It is too big./,
        'cannot encode 2**65 as an unsigned 64 bit integer'
    );
}

done_testing();
