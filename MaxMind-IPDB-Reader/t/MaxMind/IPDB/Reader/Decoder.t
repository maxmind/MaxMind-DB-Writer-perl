use strict;
use warnings;

use Test::Fatal;
use Test::More;

use MaxMind::IPDB::Reader::Decoder;

{
    my $ignored;
    open my $fh, '<', \$ignored;

    my $decoder = MaxMind::IPDB::Reader::Decoder->new(
        data_source => $fh,
    );

    my $str = 'foo';
    is(
        $decoder->_zero_pad_left( $str, 3 ),
        $str,
        'decoder does not add left padding when it is not needed'
    );

    is(
        $decoder->_zero_pad_left( $str, 4 ),
        "\x00$str",
        'decoder added one zero byte at the left of the content'
    );

    is(
        $decoder->_zero_pad_left( $str, 6 ),
        "\x00\x00\x00$str",
        'decoder added one three bytes at the left of the content'
    );
}

{
    my $data = 'this is some data';
    open my $fh, '<', \$data;

    my $decoder = MaxMind::IPDB::Reader::Decoder->new(
        data_source => $fh,
    );

    my $buffer;

    $decoder->_read( \$buffer, 0, 7 );

    is(
        $buffer,
        'this is',
        '_read( 0, 7 ) got the expected data'
    );

    $decoder->_read( \$buffer, 1, 3 );

    is(
        $buffer,
        'his',
        '_read( 1, 3 ) got the expected data'
    );

    like(
        exception { $decoder->_read( \$buffer, 5, 999 ) },
        qr{\QAttempted to read past the end of a file/memory buffer},
        'got an error when trying to read past the end of the data source'
    );

    like(
        exception { $decoder->decode() },
        qr/\QYou must provide an offset to decode from when calling ->decode/,
        'got an error when calling ->decode without an offset'
    );
}

done_testing();
