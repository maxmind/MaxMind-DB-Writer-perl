package Test::MaxMind::DB::Reader::Decoder;

use strict;
use warnings;

use MaxMind::DB::Reader::Decoder;
use List::AllUtils qw( natatime );
use Scalar::Util qw( blessed );
use Test::More;

use Exporter qw( import );

our @EXPORT_OK = qw(
    test_decoding_of_type
);

sub test_decoding_of_type {
    my $type  = shift;
    my $tests = shift;

    my $iter = natatime 2, @{$tests};
    while ( my ( $expect, $input ) = $iter->() ) {
        my $desc = "decoded $type - ";

        if ( ref $expect && !blessed $expect ) {
            $desc .=
                ref $expect eq 'HASH'
                ? 'hash with ' . ( scalar keys %{$expect} ) . ' keys'
                : 'array with ' . ( scalar @{$expect} ) . ' keys';
        }
        else {
            $desc .=
                length($expect) > 50
                ? substr( $expect, 0, 50 ) . '...(' . length($expect) . ')'
                : $expect;
        }

        my $encoded = join q{}, map { chr($_) } @{$input};
        open my $fh, '<', \$encoded;

        my $decoder = MaxMind::DB::Reader::Decoder->new(
            data_source => $fh,
        );

        # blessed objects are big ints
        if ( ref $expect && !blessed $expect ) {
            is_deeply(
                scalar $decoder->decode(0),
                $expect,
                $desc
            );
        }
        else {
            is(
                scalar $decoder->decode(0),
                ( $type eq 'double' ? $expect + 0 : $expect ),
                $desc
            );
        }
    }
}

1;
