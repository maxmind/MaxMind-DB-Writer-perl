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

has merge_record_collisions => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

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

# ABSTRACT: Tree representing a MaxMind DB database in memory - then write it to a file

__END__

=pod

=head1 SYNOPSIS

    use MaxMind::DB::Writer::Tree;
    use Net::Works::Network;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 6,
        record_size   => 24,
        database_type => 'My-IP-Data',
        languages     => ['en'],
        description   => { en => 'My database of IP data' },
    );

    my $network
        = Net::Works::Network->new_from_string( string => '8.23.0.0/16' );

    $tree->insert_network(
        $network,
        {
            color => 'blue',
            dogs  => [ 'Fido', 'Ms. Pretty Paws' ],
            size  => 42,
        },
    );

    open my $fh, '>:raw', '/path/to/my-ip-data.mmdb';
    $tree->write_tree($fh);

=head1 DESCRIPTION

This is the main class you'll use to write L<MaxMind DB database
files|http://maxmind.github.io/MaxMind-DB/>. This class represents the
database in memory. Once you've created the full tree you can write to a file.

=head1 API

This class provides the following methods:

=head2 MaxMind::DB::Writer::Tree->new()

This creates a new tree object. The constructor accepts the following
parameters:

=over 4

=item * ip_version

The IP version for the database. It must be 4 or 6.

This parameter is required.

=item * record_size

This is the record size in I<bits>. This should be one of 24, 28, 32 (in
theory any number divisible by 4 up to 128 will work but the available readers
all expect 24-32).

This parameter is required.

=item * database_type

This is a string containing the database type. This can be anything,
really. MaxMind uses strings like "GeoIP2-City", "GeoIP2-Country", etc.

This parameter is required.

=item * languages

This should be an array reference of languages used in the database, like
"en", "zh-TW", etc. This is useful as metadata for database readers and end users.

This parameter is optional.

=item * description

This is hashref where the keys are language names and the values are
descriptions of the database in that language. For example, you might have
something like:

    {
        en => 'My IP data',
        fr => 'Mon Data de IP',
    }


This parameter is required.

=item * map_key_type_callback

This is a subroutine reference that is called in order to determine how to
store each value in a map (hash) data structure. See L<DATA TYPES> below for
more details.

This parameter is optional.

=item * merge_record_collisions

By default, when an insert collides with a previous insert, the new data
simply overwrites the old data where the two networks overlap.

If this is set to true, then on a collision, the writer will merge the old
data with the new data. This only works if both inserts use a hashref for the
data payload.

This parameter is optional. It defaults to false.

=item * alias_ipv6_to_ipv4

If this is true then the final database will map some IPv6 ranges to the IPv4
range. These ranges are:

=over 8

=item * ::ffff:0:0/96

This is the IPv4-mapped IPv6 range

=item * 2001::/32

This is the Teredo range. Note that lookups for Teredo ranges will find the
Teredo server's IPv4 address, not the client's IPv4.

=item * 2002::/16

This is the 6to4 range

=back

This parameter is optional. It defaults to false.

=back

=head2 $tree->insert_network( $network, $data )

This method expects to parameters. The first is a L<Net::Works::Network>
object. The second can be any Perl data structure (except a coderef, glob, or
filehandle).

The C<$data> payload is encoded according to the L<MaxMind DB database format
spec|http://maxmind.github.io/MaxMind-DB/>. The short overview is that
anything that can be encoded in JSON can be stored in an MMDB file. It can
also handle unsigned 64-bit 128-bit integers if they are passed as
L<Math::UInt128|Math::Int128> objects.

=head2 $tree->write_tree($fh)

Given a filehandle, this method writes the contents of the tree as a MaxMind
DB database to that filehandle.

=head1 DATA TYPES

The MaxMind DB file format is strongly typed. Because Perl is not strongly
typed, you will need to explicitly specify the types for each piece of
data. Currently, this class assumes that your top-level data structure for an
IP address will always be a map (hash). You can then provide a
C<map_key_type_callback> subroutine that will be called as the data is
serialized. This callback is given a key name and is expected to return that
key's data type.

Let's use the following structure as an example:

    {
        names => {
            en => 'United States',
            es => 'Estados Unidos',
        },
        population    => 319_000_000,
        fizzle_factor => 65.7294,
        states        => [ 'Alabama', 'Alaska', ... ],
    }

Given this data structure, our C<map_key_type_callback> might look something like this:

    my %types = (
        names         => 'map',
        en            => 'utf8_string',
        es            => 'utf8_string',
        population    => 'uint32',
        fizzle_factor => 'double',
        states        => [ 'array', 'utf8_string' ],
    );

    sub {
        my $key = shift;
        return $type{$key};
    }

If the callback returns C<undef>, the serialization code will throw an
error. Note that for an array we return a 2 element arrayref where the first
element is C<'array'> and the second element is the type of content in the
array.

The valid types are:

=over 4

=item * utf8_string

=item * uint16

=item * uint32

=item * uint64

=item * uint128

=item * int32

=item * double

64 bits of precision.

=item * float

32 bits of precision.

=item * boolean

=item * map

=item * array

=back

=cut
