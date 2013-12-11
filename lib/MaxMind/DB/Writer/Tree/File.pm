package MaxMind::DB::Writer::Tree::File;

use strict;
use warnings;
use namespace::autoclean;

use IO::Handle;
use Math::Int128 qw( uint128 );
use Math::Round qw( round );
use MaxMind::DB::Common
    qw( DATA_SECTION_SEPARATOR_SIZE LEFT_RECORD RIGHT_RECORD );
use MaxMind::DB::Metadata;
use MaxMind::DB::Writer::Serializer;
use Net::Works::Network;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::StrictConstructor;

with 'MaxMind::DB::Role::Debugs';

use constant DEBUG => $ENV{MAXMIND_DB_WRITER_DEBUG};

has _map_key_type_callback => (
    is        => 'ro',
    isa       => 'CodeRef',
    init_arg  => 'map_key_type_callback',
    predicate => '_has_map_key_type_callback',
);

has _tree => (
    is       => 'ro',
    isa      => 'MaxMind::DB::Writer::Tree::InMemory',
    init_arg => 'tree',
    required => 1,
);

# All records in the tree will point to a value of this type in the data
# section.
has _root_data_type => (
    is       => 'ro',
    isa      => 'Str',              # XXX - should make sure it's valid type
    init_arg => 'root_data_type',
    default  => 'map',
);

# Will be set in BUILD so we can access it via $self->{...} later
has _record_byte_size => (
    is       => 'rw',
    writer   => '_set_record_byte_size',
    isa      => 'Int',
    init_arg => undef,
);

# Same as _record_byte_size
has _record_write_size => (
    is       => 'rw',
    writer   => '_set_record_write_size',
    isa      => 'Int',
    init_arg => undef,
);

has _node_count => (
    is       => 'ro',
    traits   => ['Number'],
    isa      => 'Int',
    init_arg => undef,
    lazy     => 1,
    default  => sub { $_[0]->_tree()->node_count() },
);

has _node_size => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_node_size',
);

has _database_type => (
    is       => 'ro',
    isa      => 'Str',
    init_arg => 'database_type',
    required => 1,
);

has _languages => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    init_arg => 'languages',
    default  => sub { [] },
);

has _description => (
    is       => 'ro',
    isa      => 'HashRef[Str]',
    init_arg => 'description',
    required => 1,
);

{
    #<<<
    my $subtype = subtype
        as 'Int',
        where { $_ == 4 || $_ == 6 };
    #>>>

    has _ip_version => (
        is       => 'ro',
        isa      => $subtype,
        init_arg => 'ip_version',
        required => 1,
    );
}

has _tree_buffer => (
    is       => 'ro',
    isa      => 'ScalarRef',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_tree_buffer',
);

has _serializer => (
    is       => 'ro',
    isa      => 'MaxMind::DB::Writer::Serializer',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_serializer',
);

sub BUILD {
    my $self = shift;

    $self->_set_record_byte_size( int( $self->_record_size() / 8 ) );
    $self->_set_record_write_size( round( $self->_record_size() / 8 ) );

    return;
}

my $DataSectionSeparator = "\0" x DATA_SECTION_SEPARATOR_SIZE;
my $MetadataMarker       = "\xab\xcd\xefMaxMind.com";

sub write_tree {
    my $self   = shift;
    my $output = shift;

    $self->_tree()->iterate($self);

    $output->print(
        substr(
            ${ $self->_tree_buffer() }, 0,
            $self->_node_size() * $self->_node_count()
        ),
        $DataSectionSeparator,
        ${ $self->_serializer()->buffer() },
        $MetadataMarker,
        $self->_encoded_metadata(),
    );
}

sub directions_for_node {
    return ( LEFT_RECORD, RIGHT_RECORD );
}

sub process_pointer_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;
    my $pointer  = shift;

    if (DEBUG) {
        $self->_debug_sprintf(
            'Writing %d[%s], node pointer = %d',
            $self->_map_node_num($node_num),
            ( $is_right ? 'right' : 'left' ),
            $self->_map_node_num($pointer)
        );
    }

    $self->_encode_record(
        $self->_map_node_num($node_num),
        $is_right,
        $self->_map_node_num($pointer),
    );

    return 1;
}

sub process_value_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;
    my $key      = shift;
    my $value    = shift;

    if ( my $pointer = $self->{_seen_data}{$key} ) {
        if (DEBUG) {
            $self->_debug_sprintf(
                'Writing %d[%s], data pointer (seen) = %d',
                $self->_map_node_num($node_num),
                ( $is_right ? 'right' : 'left' ),
                $pointer,
            );
        }

        $self->_encode_record(
            $self->_map_node_num($node_num),
            $is_right,
            $pointer,
        );
    }
    else {
        my $data_pointer = $self->_serializer()
            ->store_data( $self->_root_data_type => $value );
        $pointer
            = $data_pointer
            + $self->_node_count()
            + DATA_SECTION_SEPARATOR_SIZE;

        if (DEBUG) {
            $self->_debug_sprintf(
                'Writing %d[%s], data pointer (new) = %d',
                $self->_map_node_num($node_num),
                ( $is_right ? 'right' : 'left' ),
                $pointer,
            );

            $self->_debug_sprintf(
                '  %d = %d (data section position) + %d (node count) + %d (data section separator size)',
                $pointer,
                $data_pointer,
                $self->_node_count(),
                DATA_SECTION_SEPARATOR_SIZE,
            );
        }

        $self->_encode_record(
            $self->_map_node_num($node_num),
            $is_right,
            $pointer,
        );

        $self->{_seen_data}{$key} = $pointer;
    }

    return 1;
}

sub process_empty_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;

    if (DEBUG) {
        $self->_debug_sprintf(
            'Writing %d[%s], empty = %d',
            $self->_map_node_num($node_num),
            ( $is_right ? 'right' : 'left' ),
            $self->_node_count(),
        );
    }

    $self->_encode_record(
        $self->_map_node_num($node_num),
        $is_right,
        $self->_node_count(),
    );

    return 1;
}

sub _encode_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;
    my $value    = shift;

    my $record_size = $self->_record_size();

    # XXX - this may not work for larger record sizes unless we use a
    # Math::UInt128 to do the calculation.
    die 'Cannot store a value greater than 2**' . $record_size
        if $value > 2**$record_size;

    my $base_offset = $node_num * $self->_node_size();
    my $buffer      = $self->_tree_buffer();

    my $record_byte_size = $self->{_record_byte_size};
    my $write_size       = $self->{_record_write_size};

    my $offset = $base_offset + $is_right * $record_byte_size;

    my $encoded;
    if ( $record_size == 24 ) {
        $encoded = substr( pack( N => $value ), 1, 3 );
    }
    elsif ( $record_size == 28 ) {
        my $middle_byte = substr(
            ${$buffer},
            $offset + ( $is_right ? 0 : $record_byte_size ), 1
        );

        if ($is_right) {
            $encoded
                = pack(
                N => ( ( 0b11110000 & unpack( C => $middle_byte ) ) << 24 )
                    | $value );
        }
        else {
            $encoded = pack(
                N => ( ( $value & 0b11111111_11111111_11111111 ) << 8 ) | (
                    ( ( $value >> 20 ) & 0b11110000 )
                    | ( 0b00001111 & unpack( C => $middle_byte ) )
                )
            );
        }
    }
    elsif ( $record_size == 32 ) {
        $encoded = pack( N => $value );
    }

    substr( ${$buffer}, $offset, $write_size ) = $encoded;
}

{
    my %key_types = (
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

    my $type_callback = sub {
        return $key_types{ $_[0] } || 'utf8_string';
    };

    sub _encoded_metadata {
        my $self = shift;

        my $metadata = MaxMind::DB::Metadata->new(
            binary_format_major_version => 2,
            binary_format_minor_version => 0,
            build_epoch                 => uint128( time() ),
            database_type               => $self->_database_type(),
            description                 => $self->_description(),
            ip_version                  => $self->_ip_version(),
            languages                   => $self->_languages(),
            node_count                  => $self->_node_count(),
            record_size                 => $self->_record_size(),
        );

        my $serializer = MaxMind::DB::Writer::Serializer->new(
            map_key_type_callback => $type_callback,
        );

        $serializer->store_data( 'map', $metadata->metadata_to_encode() );

        return ${ $serializer->buffer() };
    }
}

sub _build_node_size {
    my $self = shift;

    return ( $self->_record_size() / 8 ) * 2;
}

sub _build_tree_buffer {
    my $self = shift;

    my $buffer = "\0" x ( $self->_node_size() * $self->_node_count() );

    return \$buffer;
}

sub _build_serializer {
    my $self = shift;

    return MaxMind::DB::Writer::Serializer->new(
        (
            $self->_has_map_key_type_callback()
            ? ( map_key_type_callback => $self->_map_key_type_callback() )
            : ()
        ),
    );
}

__PACKAGE__->meta()->make_immutable();

1;
