use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::Bits;
use Test::Fatal;
use Test::More;

use Bit::Vector;
use MaxMind::IPDB::Writer::Serializer;

my $strings = test_cases_for(
    'utf8_string',
    skip_huge_strings => 1,
);

{
    my $serializer = MaxMind::IPDB::Writer::Serializer->new();

    for my $i ( 0, 2, 4, 6 ) {
        $serializer->store_data( utf8_string => $strings->[$i] );
    }

    my $expect = [ map { @{ $strings->[$_] } } ( 1, 3, 5, 7 ) ];
    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer contains all strings we stored'
    );

    $serializer->store_data( utf8_string => $strings->[6] );

    push @{$expect}, @{ $strings->[7] };
    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer did not make a pointer to 3-byte string'
    );
}

{
    my $serializer = MaxMind::IPDB::Writer::Serializer->new();

    for my $i ( 4, 6, 8, 10 ) {
        $serializer->store_data( utf8_string => $strings->[$i] );
    }

    my $expect = [ map { @{ $strings->[$_] } } ( 5, 7, 9, 11 ) ];
    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer contains all strings we stored'
    );

    $serializer->store_data( utf8_string => $strings->[8] );

    push @{$expect}, ( 0b00100000, 0b00001000 );

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer contains pointer to large string instead of the string itself'
    );
}

{
    my $uint16s = test_cases_for('uint16');

    my $serializer = MaxMind::IPDB::Writer::Serializer->new();

    for my $i ( 0, 2, 4, 6 ) {
        $serializer->store_data( uint16 => $uint16s->[$i] );
    }

    my $expect = [ map { @{ $uint16s->[$_] } } ( 1, 3, 5, 7 ) ];

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored uint16s as expected'
    );

    $serializer->store_data( uint16 => $uint16s->[2] );

    push @{$expect}, @{ $uint16s->[3] };

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer does not create a pointer for a uint16'
    );
}

{
    my $uint64s = test_cases_for('uint64');

    my $serializer = MaxMind::IPDB::Writer::Serializer->new();

    for my $i ( 0, 2, 4, 6 ) {
        $serializer->store_data( uint64 => $uint64s->[$i] );
    }

    my $expect = [ map { @{ $uint64s->[$_] } } ( 1, 3, 5, 7 ) ];

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored uint64s as expected'
    );

    $serializer->store_data( uint64 => $uint64s->[2] );

    push @{$expect}, @{ $uint64s->[3] };

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer does not create a pointer for a uint64 that can be stored in one byte'
    );
}

{
    my $uint128s = test_cases_for('uint128');

    my $serializer = MaxMind::IPDB::Writer::Serializer->new();

    for my $i ( 0, 2, 4, 6 ) {
        $serializer->store_data( uint128 => $uint128s->[$i] );
    }

    my $expect = [ map { @{ $uint128s->[$_] } } ( 1, 3, 5, 7 ) ];

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored uint128s as expected'
    );

    $serializer->store_data( uint128 => $uint128s->[2] );

    push @{$expect}, @{ $uint128s->[3] };

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer does not create a pointer for a uint128 that can be stored in one byte'
    );
}

{
    my $serializer = MaxMind::IPDB::Writer::Serializer->new();

    my $int = do { use bigint; 2**128 - 1 };

    $serializer->store_data( uint128 => $int );

    my $expect = [
        0b00010000, 0b00001010,
        (0b11111111) x 16
    ];

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored 16 byte uint128 as expected'
    );

    $serializer->store_data( uint128 => $int );

    push @{$expect}, ( 0b00100000, 0b00000000 );

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored pointer to 16 byte uint128 as expected'
    );
}

{
    my $maps = test_cases_for('map');

    my $serializer = MaxMind::IPDB::Writer::Serializer->new(
        map_key_type_callback => sub { ref $_[1] ? 'map' : 'utf8_string' } );

    for my $i ( 0, 2, 4, 6 ) {
        $serializer->store_data( map => $maps->[$i] );
    }

    my $expect = [ map { @{ $maps->[$_] } } ( 1, 3, 5, 7 ) ];

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored maps as expected'
    );

    $serializer->store_data( map => $maps->[2] );

    push @{$expect}, ( 0b00100000, 0b00000001 );

    bits_is(
        ${ $serializer->buffer() },
        $expect,
        'serializer stored pointer to map as expected'
    );
}

done_testing();
