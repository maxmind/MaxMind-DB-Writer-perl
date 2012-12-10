package MaxMind::IPDB::Writer::Serializer;

use strict;
use warnings;
use namespace::autoclean;

use Carp qw( confess );
use Encode qw( encode );
use JSON::XS;
use Math::Int128 qw( uint128_to_hex );
use MaxMind::IPDB::Writer::Serializer;
use NetAddr::IP::Util qw( bcd2bin );
use Regexp::Common qw( RE_num_real );

use Moose;
use MooseX::StrictConstructor;

with 'MaxMind::IPDB::Role::Debugs';

use constant DEBUG => $ENV{MAXMIND_IPDB_SERIALIZER_DEBUG};

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
    default  => sub { {} },
    handles  => {
        _save_position     => 'set',
        _position_for_data => 'get',
    },
);

my $MinimumCacheableSize = 5;

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

    $self->_debug_string( 'Found data at position', $position )
        if DEBUG;

    if ( defined $position ) {
        $self->_store_data( pointer => $position );
    }
    else {
        my $position = $self->_store_data( $type, $data, $member_type );
        $self->_debug_string( 'Stored data at position', $position )
            if DEBUG;
        $self->_save_position( $key_for_data => $position );
    }
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

    my $current_position = length ${ $self->buffer() };

    my $method = '_encode_' . $type;
    $self->$method( $data, $member_type );

    # We don't add 1 byte because the first byte we can point to is byte 0
    # (not 1).
    return $current_position;
}

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

sub _encode_pointer {
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
        @value_bytes = split //, substr( pack( N => $value ), 1, 3 );
        $ctrl_byte |= ( 1 << 3 ) | ord( shift @value_bytes );
    }
    elsif ( $value < 2**27 ) {
        @value_bytes = split //, pack( N => $value );
        $ctrl_byte |= ( 2 << 3 ) | ord( shift @value_bytes );
    }
    else {
        @value_bytes = pack( N => $value );
        $ctrl_byte |= ( 3 << 3 );
    }

    $self->_write_encoded_data( pack( 'C', $ctrl_byte ), @value_bytes );
}

sub _encode_utf8_string {
    my $self = shift;

    $self->_simple_encode( utf8_string => encode( 'utf-8', shift ) );
}

sub _encode_double {
    my $self  = shift;
    my $value = shift;

    # This accepts values like "42." but we want to reject them, thus the
    # extra check.
    my $re = RE_num_real();
    die "The string $value does not contain a double"
        unless $value =~ /^$re$/ && $value !~ /\.$/;

    $self->_simple_encode( double => $value );
}

sub _encode_bytes {
    my $self = shift;

    $self->_simple_encode( bytes => @_ );
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
        $self->_control_bytes( $Types{map}, scalar keys %{$map} ) );

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
        $self->_control_bytes( $Types{array}, scalar @{$array} ) );

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
        $self->_control_bytes( $Types{int32}, length($encoded_value) ),
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

sub _encode_end_marker {
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
        $encoded_value = bcd2bin($value);
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

    ${ $self->buffer() } .= $_ for @_;

    return;
}

__PACKAGE__->meta()->make_immutable();

1;
