package MaxMind::IPDB::Reader::Role::Reader;

use strict;
use warnings;
use namespace::autoclean;
use autodie;

use List::AllUtils qw( min );
use MaxMind::IPDB::Reader::Decoder;
use MaxMind::IPDB::Metadata;
use Net::Works::Address;

use Moose::Role;

use constant DEBUG => $ENV{MAXMIND_IPDB_READER_DEBUG};

with 'MaxMind::IPDB::Role::Debugs', 'MaxMind::IPDB::Reader::Role::Sysreader';

has _node_byte_size => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_node_byte_size',
);

has metadata => (
    is       => 'ro',
    isa      => 'MaxMind::IPDB::Metadata',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_metadata',
    handles  => [ MaxMind::IPDB::Metadata->meta()->get_attribute_list() ],
);

has _search_tree_size => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_search_tree_size',
);

has _decoder => (
    is       => 'ro',
    isa      => 'MaxMind::IPDB::Reader::Decoder',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_decoder',
);

sub data_for_address {
    my $self = shift;
    my $addr = shift;

    my $pointer = $self->_find_address_in_tree($addr);

    return undef unless $pointer;

    return $self->_resolve_data_pointer($pointer);
}

sub _find_address_in_tree {
    my $self = shift;
    my $addr = shift;

    my $address = Net::Works::Address->new_from_string(
        string  => $addr,
        version => $self->ip_version(),
    );

    my $integer = $address->as_integer();

    if (DEBUG) {
        $self->_debug_newline();
        $self->_debug_string( 'IP Address', $address );
        $self->_debug_string( 'Integer',    $integer );
    }

    # The first node of the tree is always node 0, at the beginning of the
    # value
    my $node_num = 0;

    for my $bit_num ( reverse( 0 ... $address->bits - 1 ) ) {
        my $bit = 1 & ( $integer >> $bit_num );

        my ( $left, $right ) = $self->_read_node($node_num);

        my $record = $bit ? $right : $left;

        if (DEBUG) {
            $self->_debug_string( 'Bit #',     $address->bits() - $bit_num );
            $self->_debug_string( 'Bit value', $bit );
            $self->_debug_string( 'Record',    $bit ? 'right' : 'left' );
            $self->_debug_string( 'Record value', $record );
        }

        unless ($record) {
            $self->_debug_message('Record is empty')
                if DEBUG;
            return;
        }

        if ( $record >= $self->node_count() ) {
            $self->_debug_message('Record is a data pointer')
                if DEBUG;
            return $record;
        }

        $self->_debug_message('Record is a node number')
            if DEBUG;

        $node_num = $record;
    }
}

sub _read_node {
    my $self     = shift;
    my $node_num = shift;

    my $node = q{};
    $self->_read(
        \$node,
        $node_num * $self->_node_byte_size(),
        $self->_node_byte_size(),
    );

    return $self->_split_node_into_records($node);
}

sub _split_node_into_records {
    my $self = shift;
    my $node = shift;

    if ( $self->record_size() == 24 ) {
        return unpack( NN => pack( 'xa*xa*' => unpack( a3a3 => $node ) ) );
    }
    elsif ( $self->record_size() == 28 ) {
        my ( $left, $middle, $right ) = unpack( a3Ca3 => $node );

        return (
            unpack( N => pack( 'Ca*', ( $middle & 0xf0 ) >> 4, $left ) ),
            unpack( N => pack( 'Ca*', ( $middle & 0x0f ),      $right ) )
        );
    }
    elsif ( $self->record_size() == 32 ) {
        return unpack( NN => $node );
    }
}

sub _resolve_data_pointer {
    my $self    = shift;
    my $pointer = shift;

    $pointer = ( $pointer - $self->node_count() )
        + $self->node_count() * $self->_node_byte_size();

    $self->_debug_string( 'Resolved data pointer', $pointer )
        if DEBUG;

    # We only want the data from the decoder, not the offset where it was
    # found.
    return scalar $self->_decoder()->decode($pointer);
}

sub _build_node_byte_size {
    my $self = shift;

    return $self->record_size() * 2 / 8;
}

my $MetadataStartMarker = "\xab\xcd\xefMaxMind.com";

sub _build_metadata {
    my $self = shift;

    # We need to make sure that whatever chunk we read will have the metadata
    # in it. The description metadata key is a hash of descriptions, one per
    # language. The description could be something verbose like "GeoIP 2.0
    # City Database, Multilingual - English, Chinese (Taiwan), Chinese
    # (China), French, German, Portuguese" (but with c. 20 languages). That
    # comes out to about 250 bytes _per key_. Multiply that by 20 languages,
    # and the description alon ecould use up about 5k. The other keys in the
    # metadata are very, very tiny.
    #
    # Given all this, reading 20k seems fairly future-proof. We'd have to have
    # extremely long descriptions or descriptions in 80 languages before this
    # became too long.

    my $size = ( stat( $self->data_source() ) )[7];

    my $last_bytes = min( $size, 20 * 1024 );
    my $last_block = q{};
    $self->_read( \$last_block, -$last_bytes, $last_bytes, 'seek from end' );

    my $start = rindex( $last_block, $MetadataStartMarker );

    die 'Could not find a MaxMind IPDB metadata marker in this file ('
        . $self->file()
        . '). Is this a valid MaxMind IPDB file?'
        unless $start >= 0;

    $start += bytes::length($MetadataStartMarker);

    open my $fh, '<', \( substr( $last_block, $start ) );

    my $metadata = MaxMind::IPDB::Reader::Decoder->new(
        data_source => $fh,
    )->decode(0);

    return MaxMind::IPDB::Metadata->new($metadata);
}

sub _build_decoder {
    my $self = shift;

    return MaxMind::IPDB::Reader::Decoder->new(
        data_source  => $self->data_source(),
        pointer_base => $self->_search_tree_size(),
    );
}

sub _build_search_tree_size {
    my $self = shift;

    return $self->node_count() * $self->_node_byte_size();
}

1;
