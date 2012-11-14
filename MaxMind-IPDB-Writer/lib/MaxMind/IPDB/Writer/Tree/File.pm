package MaxMind::IPDB::Writer::Tree::File;

use strict;
use warnings;
use namespace::autoclean;

use IO::Handle;
use Math::BigInt;
use Math::Round qw( round );
use MaxMind::IPDB::Metadata;
use MaxMind::IPDB::Writer::Encoder;
use MaxMind::IPDB::Writer::Serializer;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::StrictConstructor;

has _tree => (
    is       => 'ro',
    isa      => 'MaxMind::IPDB::Writer::Tree::InMemory',
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

{
    #<<<
    my $size_type = subtype
        as 'Int',
        where { ( $_ % 4 == 0 ) && $_ >= 24 && $_ <= 128 },
        message {
            'The record size must be a numberfrom 24-128 that is divisble by 4';
        };
    #>>>

    has _record_size => (
        is       => 'ro',
        isa      => $size_type,
        init_arg => 'record_size',
        required => 1,
    );
}

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
    isa      => 'MaxMind::IPDB::Writer::Serializer',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_serializer',
);

my $MetadataMarker = "\xab\xcd\xefMaxMind.com";

sub write_tree {
    my $self   = shift;
    my $output = shift;

    my $cb = sub { $self->_write_record(@_) };
    $self->_tree()->iterate($self);

    $output->print(
        ${ $self->_tree_buffer() },
        ${ $self->_serializer()->buffer() },
        $MetadataMarker,
        $self->_encoded_metadata(),
    );
}

sub process_pointer_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;
    my $pointer  = shift;

    $self->_encode_record( $node_num, $is_right, $pointer );

    return;
}

sub process_value_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;
    my $key      = shift;
    my $value    = shift;

    if ( my $pointer = $self->{_seen_data}{$key} ) {
        $self->_encode_record( $node_num, $is_right, $pointer );
    }
    else {
        my $data_pointer = $self->_serializer()
            ->store_data( $self->_root_data_type => $value );
        $pointer = $data_pointer + $self->_tree()->node_count();

        $self->_encode_record( $node_num, $is_right, $pointer );

        $self->{_seen_data}{$key} = $pointer;
    }

    return;
}

sub process_empty_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;

    $self->_encode_record( $node_num, $is_right, 0 );
}

sub _encode_record {
    my $self     = shift;
    my $node_num = shift;
    my $is_right = shift;
    my $value    = shift;

    # XXX - this may not work for larger record sizes with bigint
    die 'Cannot store a value greater than 2**' . $self->_record_size()
        if $value > 2**$self->_record_size();

    my $base_offset = $node_num * $self->_node_size();
    my $buffer      = $self->_tree_buffer();

    my $record_byte_size = int( $self->_record_size() / 8 );
    my $write_size       = round( $self->_record_size() / 8 );

    my $offset = $base_offset + $is_right * $record_byte_size;

    my $encoded;
    if ( $self->_record_size() == 24 ) {
        $encoded = substr( pack( N => $value ), 1, 3 );
    }
    elsif ( $self->_record_size() == 28 ) {
        my $other_record = substr(
            ${$buffer}, $offset + $is_right * $record_byte_size,
            $write_size
        );

        if ($is_right) {
            $encoded
                = pack(
                N => ( ( 0xf0 & unpack( C => $other_record ) ) << 28 )
                    | $value );
        }
        else {
            $encoded = pack(
                N => (
                    ( ( $value & 0xffffff ) << 8 ) | (
                        ( ( $value >> 20 ) & 0xf0 )
                        | ( 15 & unpack( x3C => $other_record ) )
                    )
                )
            );
        }
    }
    elsif ( $self->_record_size() == 32 ) {
        $encoded = pack( N => $value );
    }

    substr( ${$buffer}, $offset, $write_size ) = $encoded;
}

sub _encoded_metadata {
    my $self = shift;

    my $metadata = MaxMind::IPDB::Metadata->new(
        binary_format_major_version => 2,
        binary_format_minor_version => 0,
        build_epoch                 => Math::BigInt->new( time() ),
        database_type               => $self->_database_type(),
        description                 => $self->_description(),
        ip_version                  => $self->_ip_version(),
        languages                   => $self->_languages(),
        node_count                  => $self->_tree->node_count(),
        record_size                 => $self->_record_size(),
    );

    my $buffer;
    open my $fh, '>', \$buffer;

    my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => $fh );
    $encoder->encode_map( $metadata->metadata_to_encode() );

    return $buffer;
}

sub _build_node_size {
    my $self = shift;

    return ( $self->_record_size() / 8 ) * 2;
}

sub _build_tree_buffer {
    my $self = shift;

    my $buffer
        = "\0" x ( $self->_node_size() * $self->_tree()->node_count() );

    return \$buffer;
}

sub _build_serializer {
    my $self = shift;

    return MaxMind::IPDB::Writer::Serializer->new();
}

__PACKAGE__->meta()->make_immutable();

1;
