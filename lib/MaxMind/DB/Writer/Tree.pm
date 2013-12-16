package MaxMind::DB::Writer::Tree;

use strict;
use warnings;

use Math::Int128 0.06 qw( uint128 );
use Math::Round qw( round );
use MaxMind::DB::Common qw(
    DATA_SECTION_SEPARATOR
    DATA_SECTION_SEPARATOR_SIZE
    METADATA_MARKER
    LEFT_RECORD
    RIGHT_RECORD
);
use MaxMind::DB::Metadata;
use MaxMind::DB::Writer::Serializer;
use Net::Works 0.13;
use Net::Works::Network;
use Sereal::Encoder;

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

has _serializer => (
    is       => 'ro',
    isa      => 'MaxMind::DB::Writer::Serializer',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_serializer',
);

{
    my $Encoder = Sereal::Encoder->new( { sort_keys => 1 } );

    sub insert_network {
        my $self   = shift;
        my $subnet = shift;
        my $data   = shift;

        if ( $subnet->version() != $self->ip_version() ) {
            my $description = $subnet->as_string();
            die 'You cannot insert an IPv'
                . $subnet->version()
                . " subnet ($description) into an IPv"
                . $self->ip_version()
                . " tree.\n";
        }

        my $key = $Encoder->encode($data);

        $self->_insert_network(
            $self->_tree(),
            $subnet->first()->as_string(),
            $subnet->mask_length(),
            $key,
            $data,
        );

        return;
    }
}

sub _build_tree {
    my $self = shift;

    return $self->_new_tree( $self->ip_version(), $self->record_size() );
}

sub write_tree {
    my $self   = shift;
    my $output = shift;

    $self->_write_search_tree(
        $self->_tree(),
        $output,
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

sub _build_node_count {
    my $self = shift;

    return $self->_node_count( $self->_tree() );
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

# This exists for the benefit of the tests.
sub lookup_ip_address {
    my $self    = shift;
    my $address = shift;

    $self->_lookup_ip_address( $self->_tree(), $address->as_string() );
}

# This is useful for diagnosing test failures
sub _dump_data_hash {
    my $self = shift;

    require Devel::Dwarn;
    Devel::Dwarn::Dwarn( $self->_data( $self->_tree ) );
}

sub DEMOLISH {
    my $self = shift;

    $self->_free_tree( $self->_tree() )
        if $self->_has_tree();

    return;
}

__PACKAGE__->meta()->make_immutable();

1;
