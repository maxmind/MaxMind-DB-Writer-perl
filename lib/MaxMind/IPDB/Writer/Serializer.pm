package MaxMind::IPDB::Writer::Serializer;

use strict;
use warnings;
use namespace::autoclean;

use Carp qw( confess );
use JSON::XS;
use MaxMind::IPDB::Writer::Encoder;

use Moose;
use MooseX::StrictConstructor;

with 'MaxMind::IPDB::Role::Debugs';

use constant DEBUG => $ENV{GEOIP2_DEBUG};

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

has _encoder => (
    is       => 'ro',
    isa      => 'MaxMind::IPDB::Writer::Encoder',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_encoder',
);

my $MinimumCacheableSize = 5;

sub store_data {
    my $self = shift;
    my $type = shift;
    my $data = shift;

    confess 'Cannot store an undef as data'
        unless defined $data;

    $self->_debug_string( 'Storing type', $type )
        if DEBUG;

    confess 'Cannot store a pointer' if $type eq 'pointer';

    return $self->_store_data( $type, $data )
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
        my $position = $self->_store_data( $type, $data );
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

# We allow blessed objects because it's possible we'll be storing bigint
# objects.
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
    my $self = shift;
    my $type = shift;
    my $data = shift;

    my $current_position = length ${ $self->buffer() };

    my $method = 'encode_' . $type;
    $self->_encoder()->$method($data);

    # We don't add 1 byte because the first byte we can point to is byte 0
    # (not 1).
    return $current_position;
}

sub _build_encoder {
    my $self = shift;

    my $buffer = $self->buffer();
    open my $fh, '>', $buffer;

    return MaxMind::IPDB::Writer::Encoder->new( output => $fh );
}

__PACKAGE__->meta()->make_immutable();

1;
