use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Writer::Serializer qw( test_encoding_of_type );
use Test::More;

test_encoding_of_type( pointer => test_cases_for('pointer') );

{
    my $serializer = MaxMind::DB::Writer::Serializer->new(
        map_key_type_callback => sub { } );

    like(
        exception { $serializer->_encode_pointer(undef) },
        qr/\QYou cannot encode undef as an unsigned 32-bit integer./,
        q{cannot encode undef as an unsigned integer}
    );

    like(
        exception { $serializer->_encode_pointer('foo') },
        qr/\QYou cannot encode foo as an unsigned 32-bit integer. It is not an unsigned integer number/,
        q{cannot encode "foo" as an unsigned integer}
    );

    like(
        exception { $serializer->_encode_pointer(-1) },
        qr/\QYou cannot encode -1 as an unsigned 32-bit integer. It is not an unsigned integer number./,
        'cannot encode -1 as an unsigned integer'
    );

    like(
        exception { $serializer->_encode_pointer( 2**33 ) },
        qr/\QYou cannot encode \E\d+\Q as an unsigned 32-bit integer. It is too big./,
        'cannot encode 2**33 as an unsigned 32-bit integer'
    );
}

done_testing();
