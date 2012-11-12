package Test::MaxMind::IPDB::Writer::Encoder;

use strict;
use warnings;

use List::AllUtils qw( all natatime );
use Math::BigInt;
use MaxMind::IPDB::Writer::Encoder;
use Scalar::Util qw( blessed );
use Test::Bits;
use Test::More;

use Exporter qw( import );

our @EXPORT_OK = qw(
    test_encoding_of_type
);

sub test_encoding_of_type {
    my $type  = shift;
    my $tests = shift;

    my $encode_method = 'encode_' . $type;

    my $iter = natatime 2, @{$tests};
    while ( my ( $input, $expect ) = $iter->() ) {
        my $desc = "packed $type - ";

        if ( ref $input && ! blessed $input ) {
            $desc .=
                ref $input eq 'HASH'
                ? 'hash with ' . ( scalar keys %{$input} ) . ' keys'
                : 'array with ' . ( scalar @{$input} ) . ' keys';
        }
        else {
            $desc .=
                length($input) > 50
                ? substr( $input, 0, 50 ) . '...(' . length($input) . ')'
                : $input;
        }

        my $output;
        open my $fh, '>', \$output;

        my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => $fh );

        $encoder->$encode_method(
            $input,
            ( $type eq 'array' ? 'utf8_string' : () ),
        );

        bits_is(
            $output,
            $expect,
            $desc
        );
    }
}

1;
