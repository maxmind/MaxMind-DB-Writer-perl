use strict;
use warnings;

use Test::Bits;
use Test::More;

use MaxMind::DB::Writer::Serializer;

my $serializer = MaxMind::DB::Writer::Serializer->new(
    map_key_type_callback => sub { 'utf8_string' } );

$serializer->store_data( map => { long_key  => 'long_value1' } );
$serializer->store_data( map => { long_key  => 'long_value2' } );
$serializer->store_data( map => { long_key2 => 'long_value1' } );
$serializer->store_data( map => { long_key2 => 'long_value2' } );
$serializer->store_data( map => { long_key  => 'long_value1' } );
$serializer->store_data( map => { long_key2 => 'long_value2' } );

bits_is(
    ${ $serializer->buffer() },
    [
        # map - 1
        0b11100001,
        (
            # long_key - 9
            0b01001000,
            0b01101100, 0b01101111, 0b01101110, 0b01100111,
            0b01011111, 0b01101011, 0b01100101, 0b01111001,
        ),
        (
            # long_value1 - 12
            0b01001011,
            0b01101100, 0b01101111, 0b01101110, 0b01100111, 0b01011111,
            0b01110110, 0b01100001, 0b01101100, 0b01110101, 0b01100101,
            0b00110001
        ),

        # map - 1
        0b11100001,
        (
            # pointer to long_key - 2
            0b00100000,
            0b00000001,
        ),
        (
            # long_value2 - 12
            0b01001011,
            0b01101100, 0b01101111, 0b01101110, 0b01100111, 0b01011111,
            0b01110110, 0b01100001, 0b01101100, 0b01110101, 0b01100101,
            0b00110010
        ),

        # map - 1
        0b11100001,
        (
            # long_key2 - 10
            0b01001001,
            0b01101100, 0b01101111, 0b01101110, 0b01100111, 0b01011111,
            0b01101011, 0b01100101, 0b01111001, 0b00110010
        ),
        (
            # pointer to long_value1 - 2
            0b00100000,
            0b00001010,
        ),

        # map - 1
        0b11100001,
        (
            # pointer to long_key2
            0b00100000,
            0b00100110,
        ),
        (
            # pointer to long_value2
            0b00100000,
            0b00011001,
        ),
        (
            # pointer to first map
            0b00100000,
            0b00000000,
        ),
        (
            # pointer to fourth map
            0b00100000,
            0b00110010,
        ),
    ],
    'keys, values, and whole maps are all deduplicated'
);

done_testing();
