package MaxMind::DB::Writer::Serializer;

use strict;
use warnings;
use namespace::autoclean;

require bytes;
use Carp qw( confess );
use Data::IEEE754 qw( pack_double_be pack_float_be );
use Encode qw( encode is_utf8 FB_CROAK );
use JSON::XS;
use Math::Int128 qw( uint128_to_net );
use MaxMind::DB::Common qw( %TypeNameToNum );

use Moose;
use MooseX::StrictConstructor;

with 'MaxMind::DB::Role::Debugs';

use constant DEBUG  => $ENV{MAXMIND_DB_SERIALIZER_DEBUG};
use constant VERIFY => $ENV{MAXMIND_DB_SERIALIZER_VERIFY};

if (VERIFY) {
    require MaxMind::DB::Reader::Decoder;
    require Test::Deep::NoTest;
    Test::Deep::NoTest->import(qw( cmp_details deep_diag));
}

binmode STDERR, ':utf8'
    if DEBUG;

has buffer => (
    is       => 'ro',
    isa      => 'ScalarRef[Str]',
    init_arg => undef,
    lazy     => 1,
    default  => sub {
        my $buffer = q{};
        return \$buffer;
    },
);

has _map_key_type_callback => (
    is       => 'ro',
    isa      => 'CodeRef',
    init_arg => 'map_key_type_callback',
    default  => sub {
        sub { }
    },
);

# This is settable so we can more easily test the encoding portion of the code
# without letting the deduplication interfere and turn a data item into a
# pointer. In normal use this should always be true.
has _deduplicate_data => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has _cache => (
    traits   => ['Hash'],
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    lazy     => 1,
    default  => sub { {} },
    handles  => {
        _save_position     => 'set',
        _position_for_data => 'get',
    },
);

has _decoder => (
    is       => 'ro',
    isa      => 'MaxMind::DB::Reader::Decoder',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_decoder',
);

my $MinimumCacheableSize = 4;

sub store_data {
    my $self        = shift;
    my $type        = shift;
    my $data        = shift;
    my $member_type = shift;

    confess 'Cannot store an undef as data'
        unless defined $data;

    $self->_debug_string( 'Storing type', $type )
        if DEBUG;

    return $self->_store_data( $type, $data, $member_type )
        unless $self->_should_cache_value( $type, $data );

    my $key_for_data = $self->_key_for_data($data);

    $self->_debug_string( 'Cache key', $key_for_data )
        if DEBUG;

    my $position = $self->_position_for_data($key_for_data);

    if ( defined $position ) {
        if (DEBUG) {
            $self->_debug_string( 'Found data at position', $position );
            $self->_debug_string( 'Storing pointer to',     $position );
        }

        return $self->_store_data( pointer => $position );
    }
    else {
        my $position = $self->_store_data( $type, $data, $member_type );
        $self->_debug_string( 'Stored data at position', $position )
            if DEBUG;
        $self->_save_position( $key_for_data => $position );

        return $position;
    }
}

if (VERIFY) {
    around store_data => sub {
        my $orig        = shift;
        my $self        = shift;
        my $type        = shift;
        my $data        = shift;
        my $member_type = shift;

        my $position = $self->$orig( $type, $data, $member_type );

        my $stored_data = $self->_decoder()->decode($position);
        my ( $ok, $stack ) = cmp_details( $data, $stored_data );

        unless ($ok) {
            my $diag = deep_diag($stack);
            die
                "Data we just stored does not decode to value we expected:\n$diag\n";
        }

        return $position;
    };
}

# These types never take more than 4 bytes to store.
my %NeverCache = map { $_ => 1 } qw(
    int32
    uint16
    uint32
);

sub _should_cache_value {
    my $self = shift;
    my $type = shift;
    my $data = shift;

    return 0 unless $self->_deduplicate_data();

    if ( $NeverCache{$type} ) {
        $self->_debug_string( 'Never cache type', $type )
            if DEBUG;
        return 0;
    }

    if ( $type eq 'uint64' || $type eq 'uint128' ) {
        my $non_zero = $data =~ s/^0+//r;

        my $stored_bytes = ( length($non_zero) / 4 );

        $self->_debug_string( "Space needed for $type $data", $stored_bytes )
            if DEBUG;

        # We can store four hex digits per byte. Once we strip leading zeros,
        # we know how much space this number will take to store.
        return $stored_bytes >= $MinimumCacheableSize;
    }
    elsif ( ref $data ) {
        $self->_debug_message('Always cache references')
            if DEBUG;
        return 1;
    }
    else {
        $self->_debug_string(
            "Space needed for $type $data",
            bytes::length $data
        ) if DEBUG;

        return bytes::length($data) >= $MinimumCacheableSize;
    }
}

# We allow blessed objects because it's possible we'll be storing
# Math::UInt128 objects.
my $json = JSON::XS->new()->canonical()->allow_blessed();

sub _key_for_data {
    my $self = shift;
    my $data = shift;

    if ( ref $data ) {

        # Based on our benchmarks JSON::XS is about twice as fast as Storable.
        return $json->encode($data);
    }
    else {
        return $data;
    }
}

sub _store_data {
    my $self        = shift;
    my $type        = shift;
    my $data        = shift;
    my $member_type = shift;

    my $current_position = bytes::length ${ $self->buffer() };

    my $method = '_encode_' . $type;
    $self->$method( $data, $member_type );

    # We don't add 1 byte because the first byte we can point to is byte 0
    # (not 1).
    return $current_position;
}

my @pointer_thresholds;
push @pointer_thresholds,
    {
    cutoff => 2**11,
    offset => 0,
    };
push @pointer_thresholds,
    {
    cutoff => 2**19 + $pointer_thresholds[-1]{cutoff},
    offset => $pointer_thresholds[-1]{cutoff},
    };
push @pointer_thresholds,
    {
    cutoff => 2**27 + $pointer_thresholds[-1]{cutoff},
    offset => $pointer_thresholds[-1]{cutoff},
    };
push @pointer_thresholds,
    {
    cutoff => 2**32,
    offset => 0,
    };

sub _encode_pointer {
    my $self  = shift;
    my $value = shift;

    $self->_require_x_bits_unsigned_integer( 32, $value );

    my $ctrl_byte = ord( $self->_control_bytes( $TypeNameToNum{pointer}, 0 ) );

    my @value_bytes;
    for my $n ( 0 .. 3 ) {
        if ( $value < $pointer_thresholds[$n]{cutoff} ) {

            my $pack_method = '_pack_' . ( $n + 1 ) . '_byte_pointer';
            @value_bytes = split //,
                $self->$pack_method(
                $value - $pointer_thresholds[$n]{offset} );

            if ( $n == 3 ) {
                $ctrl_byte |= ( 3 << 3 );
            }
            else {
                $ctrl_byte |= ( $n << 3 ) | ord( shift @value_bytes );
            }

            last;
        }
    }

    $self->_write_encoded_data( pack( 'C', $ctrl_byte ), @value_bytes );
}

sub _pack_1_byte_pointer {
    return pack( n => $_[1] );
}

sub _pack_2_byte_pointer {
    return substr( pack( N => $_[1] ), 1, 3 );
}

sub _pack_3_byte_pointer {
    return pack( N => $_[1] );
}

sub _pack_4_byte_pointer {
    return pack( N => $_[1] );
}

sub _encode_utf8_string {
    my $self = shift;

    my $string = shift;

    $self->_simple_encode(
        utf8_string => encode( 'UTF-8', $string, FB_CROAK ) );
}

sub _encode_double {
    my $self = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{double}, 8, ),
        pack_double_be(shift)
    );
}

sub _encode_float {
    my $self = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{float}, 4, ),
        pack_float_be(shift)
    );
}

sub _encode_bytes {
    my $self = shift;

    my $bytes = shift;
    die "You attempted to store a characters string ($bytes) as bytes"
        if is_utf8($bytes);

    $self->_simple_encode( bytes => $bytes );
}

sub _encode_uint16 {
    my $self = shift;

    $self->_encode_unsigned_int( 16 => @_ );
}

sub _encode_uint32 {
    my $self = shift;

    $self->_encode_unsigned_int( 32 => @_ );
}

sub _encode_map {
    my $self = shift;
    my $map  = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{map}, scalar keys %{$map} ) );

    # We sort to make testing possible.
    for my $k ( sort keys %{$map} ) {
        $self->store_data( utf8_string => $k );

        my $value_type = $self->_type_for_key( $k, $map->{$k} );
        my $array_value_type;
        if ( ref $value_type ) {
            ( $value_type, $array_value_type ) = @{$value_type};
        }

        $self->store_data( $value_type, $map->{$k}, $array_value_type );
    }
}

sub _encode_array {
    my $self       = shift;
    my $array      = shift;
    my $value_type = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{array}, scalar @{$array} ) );

    $self->store_data( $value_type, $_ ) for @{$array};
}

sub _type_for_key {
    my $self  = shift;
    my $key   = shift;
    my $value = shift;

    my $type = $self->_map_key_type_callback->( $key, $value );

    die qq{Could not determine the type for map key "$key"}
        unless $type;

    return $type;
}

sub _encode_int32 {
    my $self  = shift;
    my $value = shift;

    my $encoded_value = pack( 'N!' => $value );
    $encoded_value =~ s/^\x00+//;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{int32}, length($encoded_value) ),
        $encoded_value,
    );
}

sub _encode_uint64 {
    my $self = shift;

    $self->_encode_unsigned_int( 64 => @_ );
}

sub _encode_uint128 {
    my $self = shift;

    $self->_encode_unsigned_int( 128 => @_ );
}

sub _encode_boolean {
    my $self  = shift;
    my $value = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{boolean}, $value ? 1 : 0 ) );
}

sub _encode_end_marker {
    my $self = shift;

    $self->_simple_encode( 'end_marker', q{} );
}

sub _simple_encode {
    my $self  = shift;
    my $type  = shift;
    my $value = shift;

    $self->_write_encoded_data(
        $self->_control_bytes( $TypeNameToNum{$type}, length($value) ),
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
        $encoded_value = uint128_to_net($value);
    }
    else {
        $encoded_value = pack( N => $value );
    }

    $encoded_value =~ s/^\x00+//;

    $self->_write_encoded_data(
        $self->_control_bytes(
            $TypeNameToNum{ 'uint' . $bits },
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

        die "You cannot encode undef as an $type_description."
            unless defined $value;

        if ( $bits >= 64 ) {
            if ( blessed $value && $value->isa('Math::UInt128') ) {
                die
                    "You cannot encode $value as an $type_description. It is too big."
                    if $bits != 128 && $value / ( 2**$bits ) > 1;
            }
            else {
                die
                    "You cannot encode $value as an $type_description. It is not an unsigned integer number."
                    unless $value =~ /^[0-9]+$/;
            }
        }
        else {
            die
                "You cannot encode $value as an $type_description. It is not an unsigned integer number."
                unless $value =~ /^[0-9]+$/;

            die
                "You cannot encode $value as an $type_description. It is too big."
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
            $first_byte  = ( $TypeNameToNum{extended} << 5 );
            $second_byte = $type - 7;
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

    ${ $self->buffer() } .= $_ for @_;

    $self->_debug_binary( 'Wrote', join q{}, @_ )
        if DEBUG;

    return;
}

sub _build_decoder {
    my $self = shift;

    open my $fh, '<:raw', $self->buffer();

    return MaxMind::DB::Reader::Decoder->new(
        data_source => $fh,
    );
}

__PACKAGE__->meta()->make_immutable();

1;
