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

        my $encoder = MaxMind::IPDB::Writer::Encoder->new(
            output                => $fh,
            map_key_type_callback => \&_map_key_type,
        );

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

my %geoip_keys = (
    area_code   => 'utf8_string',
    description => 'map',
    geonames_id => 'uint32',
    latitude    => 'double',
    location_id => 'uint32',
    longitude   => 'double',
    metro_code  => 'uint16',
    name        => 'map',
    postal_code => 'utf8_string',
);

my %metadata_keys = (
    binary_format_major_version => 'uint16',
    binary_format_minor_version => 'uint16',
    build_epoch                 => 'uint64',
    database_type               => 'utf8_string',
    description                 => 'map',
    ip_version                  => 'uint16',
    languages                   => [ 'array', 'utf8_string' ],
    node_count                  => 'uint32',
    record_size                 => 'uint32',
);

sub _map_key_type {
    my $key  = shift;

    # locale id
    return 'utf8_string' if $key =~ /^[a-z]{2,3}(?:-[A-Z]{2})?$/;

    return $geoip_keys{$key} || $metadata_keys{$key};
}

1;
