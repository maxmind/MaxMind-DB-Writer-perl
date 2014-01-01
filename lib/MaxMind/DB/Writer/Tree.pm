package MaxMind::DB::Writer::Tree;

use strict;
use warnings;
use namespace::autoclean;

use IO::Handle;
use Math::Int128 0.06 qw( uint128 );
use MaxMind::DB::Common 0.031003 qw(
    DATA_SECTION_SEPARATOR
    METADATA_MARKER
);
use MaxMind::DB::Metadata;
use MaxMind::DB::Writer::Serializer;
use MaxMind::DB::Writer::Util qw( key_for_data );
use Net::Works 0.16;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::StrictConstructor;

use XSLoader;

XSLoader::load(
    __PACKAGE__,
    exists $MaxMind::DB::Writer::Tree::{VERSION}
        && ${ $MaxMind::DB::Writer::Tree::{VERSION} }
    ? ${ $MaxMind::DB::Writer::Tree::{VERSION} }
    : '42'
);

has ip_version => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

{
    #<<<
    my $size_type = subtype
        as 'Int',
        where { ( $_ % 4 == 0 ) && $_ >= 24 && $_ <= 128 },
        message {
            'The record size must be a number from 24-128 that is divisible by 4';
        };
    #>>>

    has record_size => (
        is       => 'ro',
        isa      => $size_type,
        required => 1,
    );
}

has node_count => (
    is       => 'ro',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_node_count',
);

has _tree => (
    is        => 'ro',
    init_arg  => undef,
    lazy      => 1,
    builder   => '_build_tree',
    predicate => '_has_tree',
);

# All records in the tree will point to a value of this type in the data
# section.
has _root_data_type => (
    is       => 'ro',
    isa      => 'Str',              # XXX - should make sure it's valid type
    init_arg => 'root_data_type',
    default  => 'map',
);

has _map_key_type_callback => (
    is        => 'ro',
    isa       => 'CodeRef',
    init_arg  => 'map_key_type_callback',
    predicate => '_has_map_key_type_callback',
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

has _alias_ipv6_to_ipv4 => (
    is       => 'ro',
    isa      => 'Bool',
    default  => 0,
    init_arg => 'alias_ipv6_to_ipv4',
);

has _serializer => (
    is       => 'ro',
    isa      => 'MaxMind::DB::Writer::Serializer',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_serializer',
);

# The XS code expects $self->{_tree} to be populated.
sub BUILD {
    $_[0]->_tree();
}

sub insert_network {
    my $self    = shift;
    my $network = shift;
    my $data    = shift;

    if ( $network->version() != $self->ip_version() ) {
        my $description = $network->as_string();
        die 'You cannot insert an IPv'
            . $network->version()
            . " network ($description) into an IPv"
            . $self->ip_version()
            . " tree.\n";
    }

    $self->_insert_network(
        $network->first()->as_string(),
        $network->mask_length(),
        key_for_data($data),
        $data,
    );

    return;
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

# This is useful for diagnosing test failures
sub _dump_data_hash {
    my $self = shift;

    require Devel::Dwarn;
    Devel::Dwarn::Dwarn( $self->_data() );
}

sub write_tree {
    my $self   = shift;
    my $output = shift;

    $self->_write_search_tree(
        $output,
        $self->_alias_ipv6_to_ipv4(),
        $self->_root_data_type(),
        $self->_serializer(),
    );

    $output->print(
        DATA_SECTION_SEPARATOR,
        ${ $self->_serializer()->buffer() },
        METADATA_MARKER,
        $self->_encoded_metadata(),
    );
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
        record_size                 => 'uint16',
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
            ip_version                  => $self->ip_version(),
            languages                   => $self->_languages(),
            node_count                  => $self->node_count(),
            record_size                 => $self->record_size(),
        );

        my $serializer = MaxMind::DB::Writer::Serializer->new(
            map_key_type_callback => $type_callback,
        );

        $serializer->store_data( 'map', $metadata->metadata_to_encode() );

        return ${ $serializer->buffer() };
    }
}

sub DEMOLISH {
    my $self = shift;

    $self->_free_tree()
        if $self->_has_tree();

    return;
}

__PACKAGE__->meta()->make_immutable();

1;
