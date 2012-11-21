package MaxMind::IPDB::Writer::Encoder;

use strict;
use warnings;
use namespace::autoclean;
use bytes;

use Bit::Vector;
use Encode qw( encode );
use List::AllUtils qw( sum );
use Regexp::Common qw( RE_num_real );

use Moose;
use MooseX::StrictConstructor;

has _map_key_type_callback => (
    is       => 'ro',
    isa      => 'CodeRef',
    init_arg => 'map_key_type_callback',
    default  => sub {
        sub { }
    },
);

has _output => (
    is       => 'ro',
    isa      => 'FileHandle',
    init_arg => 'output',
    required => 1,
);

my %Types = (
    extended    => 0,
    pointer     => 1,
    utf8_string => 2,
    double      => 3,
    bytes       => 4,
    uint16      => 5,
    uint32      => 6,
    map         => 7,
    int32       => 8,
    uint64      => 9,
    uint128     => 10,
    array       => 11,
    container   => 12,
    end_marker  => 13,
);

sub encode_pointer {
    my $self  = shift;
    my $value = shift;

    $self->_require_x_bits_unsigned_integer( 32, $value );

    my $ctrl_byte = ord( $self->_control_bytes( $Types{pointer}, 0 ) );

    my @value_bytes;
    if ( $value < 2**11 ) {
        @value_bytes = split //, pack( n => $value );
        $ctrl_byte |= ord( shift @value_bytes );
    }
    elsif ( $value < 2**19 ) {
        @value_bytes = split //, substr( pack( N => $value - 2**11 ), 1 );
        $ctrl_byte |= ( 1 << 3 ) | ord( shift @value_bytes );
    }
    elsif ( $value < 2**27 ) {
        @value_bytes = split //, pack( N => $value - 2**19 );
        $ctrl_byte |= ( 2 << 3 ) | ord( shift @value_bytes );
    }
    else {
        @value_bytes = pack( N => $value );
        $ctrl_byte |= ( 3 << 3 );
    }

    $self->_write_encoded_data( pack( 'C', $ctrl_byte ), @value_bytes );
}


sub encode_utf8_string {
    my $self = shift;

    $self->_simple_encode( utf8_string => encode( 'utf-8', shift ) );
}

sub encode_double {
    my $self  = shift;
    my $value = shift;

    # This accepts values like "42." but we want to reject them, thus the
    # extra check.
    my $re = RE_num_real();
    die "The string $value does not contain a double"
        unless $value =~ /^$re$/ && $value !~ /\.$/;

    $self->_simple_encode( double => $value );
}

sub encode_bytes {
    my $self = shift;

    $self->_simple_encode( bytes => @_ );
}

sub encode_uint16 {
    my $self = shift;

    $self->_encode_unsigned_int( 16 => @_ );
}

sub encode_uint32 {
    my $self = shift;

    $self->_encode_unsigned_int( 32 => @_ );
}

sub encode_map {
    my $self = shift;
    my $map  = shift;

    $self->_output()
        ->print( $self->_control_bytes( $Types{map}, scalar keys %{$map} ) );

    # We sort to make testing possible.
    for my $k ( sort keys %{$map} ) {
        $self->encode_utf8_string($k);

        my $value_type = $self->_type_for_key( $k, $map->{$k} );
        my $array_value_type;

        if ( ref $value_type ) {
            ( $value_type, $array_value_type ) = @{$value_type};
        }

        my $encode_method = 'encode_' . $value_type;

        $self->$encode_method( $map->{$k}, $array_value_type );
    }
}

sub encode_array {
    my $self       = shift;
    my $array      = shift;
    my $value_type = shift;

    $self->_output()
        ->print( $self->_control_bytes( $Types{array}, scalar @{$array} ) );

    my $encode_method = 'encode_' . $value_type;

    $self->$encode_method($_) for @{$array};
}

{
    my %KnownKeys = (
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

    sub _type_for_key {
        my $self  = shift;
        my $key   = shift;
        my $value = shift;

        my $type = $self->_map_key_type_callback->( $key, $value )
            || $KnownKeys{$key};

        die qq{Could not determine the type for map key "$key"}
            unless $type;

        return $type;
    }
}

sub encode_int32 {
    my $self  = shift;
    my $value = shift;

    my $encoded_value = pack( 'N!' => $value );
    $encoded_value =~ s/^\x00+//;

    $self->_write_encoded_data(
        $self->_control_bytes( $Types{int32}, length($encoded_value) ),
        $encoded_value,
    );
}

sub encode_uint64 {
    my $self = shift;

    $self->_encode_unsigned_int( 64 => @_ );
}

sub encode_uint128 {
    my $self = shift;

    $self->_encode_unsigned_int( 128 => @_ );
}

sub encode_end_marker {
    my $self = shift;

    $self->_simple_encode( 'end_marker', q{} );
}

sub _simple_encode {
    my $self  = shift;
    my $type  = shift;
    my $value = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $Types{$type}, length($value) ),
        $value,
    );
}

sub _encode_unsigned_int {
    my $self  = shift;
    my $bits  = shift;
    my $value = shift;

    $self->_require_x_bits_unsigned_integer( $bits, $value );

    my $encoded_value;
    if ( $bits >= 64 ) {
        my $hex = blessed $value ? $value->as_hex() : $value;

        $hex =~ s/^0x//;
        $hex = sprintf( '%0' . ( $bits / 4 ) . 's', $hex );

        $encoded_value = pack(
            'N*',
            map { hex( substr( $hex, $_ * 8, 8 ) ) } 0 .. ( $bits / 32 ) - 1
        );
    }
    else {
        $encoded_value = pack( N => $value );
    }

    $encoded_value =~ s/^\x00+//;

    $self->_write_encoded_data(
        $self->_control_bytes(
            $Types{ 'uint' . $bits },
            length($encoded_value)
        ),
        $encoded_value,
    );
}

{
    my %Max = (
        16 => ( 2**16 ) - 1,
        32 => ( 2**32 ) - 1,
    );

    sub _require_x_bits_unsigned_integer {
        my $self  = shift;
        my $bits  = shift;
        my $value = shift;

        my $type_description = "unsigned $bits-bit integer";

        die "You cannot encode undef as a $type_description."
            unless defined $value;

        if ( $bits >= 64 ) {
            return if blessed $value && $value->isa('Math::BigInt');

            die
                "You cannot encode $value as a $type_description. It is not a hex number."
                unless $value =~ /^[0-9a-fA-F]+$/;

            die
                "You cannot encode $value as a $type_description. It is too big."
                if length $value > $bits / 4;
        }
        else {
            die
                "You cannot encode $value as a $type_description. It is not an unsigned integer number."
                unless $value =~ /^[0-9]+$/;

            die
                "You cannot encode $value as a $type_description. It is too big."
                if $value > $Max{$bits};

        }
    }
}

{
    # The value is the threshold for needing another byte to store the size
    # value. In other words, a size of 28 fits in one byte, a size of 29 needs
    # two bytes.
    my %ThresholdSize = (
        1 => 29,
        2 => 29 + 256,
        3 => 29 + 256 + 2**16,
        4 => 29 + 256 + 2**16 + 2**24,
    );

    sub _control_bytes {
        my $self = shift;
        my $type = shift;
        my $size = shift;

        if ( $size >= $ThresholdSize{4} ) {
            die "Cannot store $size bytes - max size is "
                . ( $ThresholdSize{4} - 1 )
                . ' bytes';
        }

        my $template = 'C';

        my $first_byte;
        my $second_byte;
        if ( $type < 8 ) {
            $first_byte = ( $type << 5 );
        }
        else {
            $first_byte  = ( $Types{extended} << 5 );
            $second_byte = $type;
            $template .= 'C';
        }

        my $leftover_size;
        if ( $size < $ThresholdSize{1} ) {
            $first_byte |= $size;
        }
        elsif ( $size <= $ThresholdSize{2} ) {
            $first_byte |= 29;
            $leftover_size = $size - $ThresholdSize{1};
            $template .= 'C';
        }
        elsif ( $size <= $ThresholdSize{3} ) {
            $first_byte |= 30;
            $leftover_size = $size - $ThresholdSize{2};
            $template .= 'n';
        }
        elsif ( $size <= $ThresholdSize{4} ) {
            $first_byte |= 31;

            # There's no nice way to express "pack an integer into 24 bits"
            # using a pack template, so we'll just pack it here and then chop
            # off the first byte.
            $leftover_size
                = substr( pack( N => $size - $ThresholdSize{3} ), 1 );
            $template .= 'a3';
        }

        return pack(
            $template => grep { defined } (
                $first_byte,
                $second_byte,
                $leftover_size,
            )
        );
    }
}

sub _write_encoded_data {
    my $self    = shift;
    my @encoded = @_;

    $self->_output()->print(@encoded);
}

__PACKAGE__->meta()->make_immutable();

1;
