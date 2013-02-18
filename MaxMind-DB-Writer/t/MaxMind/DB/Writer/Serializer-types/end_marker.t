use strict;
use warnings;

use lib 't/lib';

use Test::Bits;
use Test::More;

use MaxMind::IPDB::Writer::Serializer;

{
    my $serializer = MaxMind::IPDB::Writer::Serializer->new();
    $serializer->_encode_end_marker();

    bits_is(
        ${ $serializer->buffer() },
        [ 0b00000000, 0b00000110 ],
        'encoding of end_marker type'
    );
}

done_testing();
