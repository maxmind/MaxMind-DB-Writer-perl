use strict;
use warnings;

use lib 't/lib';

use Test::Bits;
use Test::Fatal;
use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Writer::Serializer qw( test_encoding_of_type );
use Test::More;

{
    my $tb = Test::Builder->new();

    binmode $_, ':encoding(UTF-8)'
        for $tb->output(),
        $tb->failure_output(),
        $tb->todo_output();
}


test_encoding_of_type( utf8_string => test_cases_for('utf8_string') );

my $max_size = ( 2**24 - 1 ) + 65821;
_test_long_string(
    $max_size,
    [ 0b01011111, 0b11111111, 0b11111111, 0b11111111, ],
);

{
    my $string_too_big = 'x' x ( $max_size + 1 );

    my $serializer = MaxMind::DB::Writer::Serializer->new();

    like(
        exception { $serializer->_encode_utf8_string($string_too_big) },
        qr/\QCannot store 16843037 bytes - max size is 16843036 bytes/,
        "encoder dies when asked to encode more than $max_size bytes of data"
    );
}

done_testing();

sub _test_long_string {
    my $length = shift;
    my $first_4 = shift;

    my $serializer = MaxMind::DB::Writer::Serializer->new();

    my $string = 'x' x $length;

    $serializer->store_data( utf8_string => $string );

    bits_is(
        substr( ${ $serializer->buffer() }, 0, 4 ),
        $first_4,
        "first four bytes contain expected value for long string ($length bytes)"
    );

    bits_is(
        substr( ${ $serializer->buffer() }, 5, 500 ),
        [ ( ord('x') ) x 500 ],
        "next 500 bytes contain encoding of x ($length bytes)"
    );

    my $expect = $length + 4;
    is(
        length ${ $serializer->buffer() },
        $expect,
        "$length byte string is $expect bytes when encoded"
    );
}
