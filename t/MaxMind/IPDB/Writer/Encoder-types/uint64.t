use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Encoder qw( test_encoding_of_type );
use Test::More;

use MaxMind::IPDB::Writer::Encoder;

test_encoding_of_type( uint64 => test_cases_for('uint64') );

{
    my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => \*STDOUT );

    like(
        exception { $encoder->encode_uint64(undef) },
        qr/\QYou cannot encode undef as a unsigned 64-bit integer./,
        q{cannot encode undef as an unsigned integer}
    );

    like(
        exception { $encoder->encode_uint64('foo') },
        qr/\QYou cannot encode foo as a unsigned 64-bit integer. It is not a hex number./,
        q{cannot encode "foo" as an unsigned integer}
    );

    like(
        exception { $encoder->encode_uint64(-1) },
        qr/\QYou cannot encode -1 as a unsigned 64-bit integer. It is not a hex number./,
        'cannot encode -1 as an unsigned integer'
    );

    like(
        exception {
            $encoder->encode_uint64(
                Bit::Vector->new_Bin( 65 => '1' x 65 )->to_Hex() );
        },
        qr/\QYou cannot encode \E[\dA-F]+\Q as a unsigned 64-bit integer. It is too big./,
        'cannot encode 2**65 as an unsigned 64 bit integer'
    );
}

done_testing();
