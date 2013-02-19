package MaxMind::DB::Reader::Role::Reader;

use strict;
use warnings;
use namespace::autoclean;
use autodie;

use MaxMind::DB::Reader::Decoder;
use Net::Works::Address;

use Moose::Role;

use constant DEBUG => $ENV{MAXMIND_DB_READER_DEBUG};

my $DataSectionStartMarkerSize = 16;

with 'MaxMind::DB::Role::Debugs', 'MaxMind::DB::Reader::Role::NodeReader';

has _node_byte_size => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_node_byte_size',
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
    isa      => 'MaxMind::DB::Reader::Decoder',
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
        $self->_debug_string( 'IP address',      $address );
        $self->_debug_string( 'IP address bits', $address->as_bit_string() );
        $self->_debug_newline();
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

        if ( $record == $self->node_count() ) {
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

sub _resolve_data_pointer {
    my $self    = shift;
    my $pointer = shift;

    my $resolved
        = ( $pointer - $self->node_count() ) + $self->_search_tree_size();

    if (DEBUG) {
        my $node_count = $self->node_count();
        my $tree_size  = $self->_search_tree_size();

        $self->_debug_string(
            'Resolved data pointer',
            "( $pointer - $node_count ) + $tree_size = $resolved"
        );
    }

    # We only want the data from the decoder, not the offset where it was
    # found.
    return scalar $self->_decoder()->decode($resolved);
}

sub _build_node_byte_size {
    my $self = shift;

    return $self->record_size() * 2 / 8;
}

sub _build_decoder {
    my $self = shift;

    return MaxMind::DB::Reader::Decoder->new(
        data_source  => $self->data_source(),
        pointer_base => $self->_search_tree_size() + $DataSectionStartMarkerSize,
    );
}

sub _build_search_tree_size {
    my $self = shift;

    return $self->node_count() * $self->_node_byte_size();
}

around _build_metadata => sub {
    my $orig = shift;
    my $self = shift;

    return $self->$orig(@_) unless DEBUG;

    my $metadata = $self->$orig(@_);

    $metadata->debug_dump();

    return $metadata;
};

1;
