use strict;
use warnings;

use Test::Bits;
use Test::More;

use MaxMind::DB::Reader::Decoder;
use MaxMind::DB::Writer::Serializer;

my $serializer = MaxMind::DB::Writer::Serializer->new(
    map_key_type_callback => sub { 'utf8_string' } );

my $first_short_string = 'a short string';
$serializer->store_data( utf8_string => $first_short_string );

my $four_byte_pointer_threshold = 134744064;

my $long_string = 'a' x 2**16;
while ( length ${ $serializer->buffer() } < $four_byte_pointer_threshold ) {
    $serializer->store_data( utf8_string => $long_string++ );
}

$MaxMind::DB::Writer::Serializer::DEBUG = 1;
my $small_pointer = $serializer->store_data( utf8_string => $first_short_string );

my $last_short_string = 'another short string';

$serializer->store_data( utf8_string => $last_short_string );
my $large_pointer = $serializer->store_data( utf8_string => $last_short_string );

my $buffer = $serializer->buffer();
open my $fh, '<:raw', $buffer;

my $decoder = MaxMind::DB::Reader::Decoder->new(
    data_source       => $fh,
    _data_source_size => bytes::length( ${$buffer} ),
);

{
    is(
        scalar $decoder->decode(0),
        $first_short_string,
        'decoded short string at beginning of encoded data'
    );

    is(
        scalar $decoder->decode( ( length $first_short_string ) + 1 ),
        ( 'a' x 2**16 ),
        'decoded first long string after short string'
    );

    is(
        scalar $decoder->decode($small_pointer),
        $first_short_string,
        'decoded small pointer'
    );

    is(
        scalar $decoder->decode($large_pointer),
        $last_short_string,
        'decoded large pointer'
    );
}

done_testing();
