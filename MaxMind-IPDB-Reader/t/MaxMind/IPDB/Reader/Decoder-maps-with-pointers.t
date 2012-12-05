use strict;
use warnings;

use Test::Bits;
use Test::More;

use MaxMind::IPDB::Reader::Decoder;
use MaxMind::IPDB::Writer::Serializer;

my $serializer = MaxMind::IPDB::Writer::Serializer->new(
    map_key_type_callback => sub { 'utf8_string' } );

$serializer->store_data( map => { long_key  => 'long_value1' } );
$serializer->store_data( map => { long_key  => 'long_value2' } );
$serializer->store_data( map => { long_key2 => 'long_value1' } );
$serializer->store_data( map => { long_key2 => 'long_value2' } );
$serializer->store_data( map => { long_key  => 'long_value1' } );
$serializer->store_data( map => { long_key2 => 'long_value2' } );

open my $fh, '<', $serializer->buffer();

my $decoder = MaxMind::IPDB::Reader::Decoder->new( data_source => $fh );

my %tests = (
    0  => { long_key  => 'long_value1' },
    22 => { long_key  => 'long_value2' },
    37 => { long_key2 => 'long_value1' },
    50 => { long_key2 => 'long_value2' },
    55 => { long_key  => 'long_value1' },
    57 => { long_key2 => 'long_value2' },
);

for my $offset ( sort keys %tests ) {
    is_deeply(
        scalar $decoder->decode($offset),
        $tests{$offset},
        "decoded expected data structure at offset $offset"
    );
}

done_testing();
