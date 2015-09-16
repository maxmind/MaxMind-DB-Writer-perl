package MaxMind::DB::Writer::Tree;

use strict;
use warnings;
use namespace::autoclean;
use autodie;

our $VERSION = '0.100005';

use IO::Handle;
use Math::Int64 0.51;
use Math::Int128 0.21 qw( uint128 );
use MaxMind::DB::Common 0.031003 qw(
    DATA_SECTION_SEPARATOR
    METADATA_MARKER
);
use MaxMind::DB::Metadata;
use MaxMind::DB::Writer::Serializer;
use MaxMind::DB::Writer::Util qw( key_for_data );
use MooseX::Params::Validate qw( validated_list );
use Net::Works 0.20;
use Sereal::Decoder qw( decode_sereal );
use Sereal::Encoder qw( encode_sereal );

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::StrictConstructor;

use XSLoader;

XSLoader::load( __PACKAGE__, $VERSION );

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

has map_key_type_callback => (
    is       => 'ro',
    isa      => 'CodeRef',
    required => 1,
);

has database_type => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has languages => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

has description => (
    is       => 'ro',
    isa      => 'HashRef[Str]',
    required => 1,
);

has alias_ipv6_to_ipv4 => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has _serializer => (
    is       => 'ro',
    isa      => 'MaxMind::DB::Writer::Serializer',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_serializer',
);

# This is an attribute so that we can explicitly set it from test code when we
# want to compare the binary output for two trees that we want to be
# identical.
has _build_epoch => (
    is      => 'rw',
    writer  => '_set_build_epoch',
    isa     => 'Int',
    lazy    => 1,
    default => sub { time() },
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
        $network->prefix_length(),
        key_for_data($data),
        $data,
    );

    return;
}

sub _build_serializer {
    my $self = shift;

    return MaxMind::DB::Writer::Serializer->new(
        map_key_type_callback => $self->map_key_type_callback(),
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
        $self->alias_ipv6_to_ipv4(),
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
            build_epoch                 => uint128( $self->_build_epoch() ),
            database_type               => $self->database_type(),
            description                 => $self->description(),
            ip_version                  => $self->ip_version(),
            languages                   => $self->languages(),
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

{
    my %do_not_freeze = map { $_ => 1 } qw(
        map_key_type_callback
        _tree
    );

    sub freeze_tree {
        my $self     = shift;
        my $filename = shift;

        my %constructor_params;
        for my $attr ( $self->meta()->get_all_attributes() ) {
            next unless $attr->init_arg();
            next if $do_not_freeze{ $attr->name() };

            my $reader = $attr->get_read_method();
            $constructor_params{ $attr->init_arg() } = $self->$reader();
        }

        my $frozen = encode_sereal( \%constructor_params );
        $self->_freeze_tree( $filename, $frozen, length $frozen );

        return;
    }
}

sub new_from_frozen_tree {
    my $class = shift;
    my ( $filename, $callback, $database_type, $description )
        = validated_list(
        \@_,
        filename              => { isa => 'Str' },
        map_key_type_callback => { isa => 'CodeRef' },
        database_type         => { isa => 'Str', optional => 1 },
        description           => { isa => 'HashRef[Str]', optional => 1 },
        );

    open my $fh, '<:raw', $filename;
    my $packed_params_size;
    unless ( read( $fh, $packed_params_size, 4 ) == 4 ) {
        die "Could not read 4 bytes from $filename: $!";
    }

    my $params_size = unpack( 'L', $packed_params_size );
    my $frozen_params;
    unless ( read( $fh, $frozen_params, $params_size ) == $params_size ) {
        die "Could not read $params_size bytes from $filename: $!";
    }
    my $params = decode_sereal($frozen_params);

    $params->{database_type} = $database_type if defined $database_type;
    $params->{description}   = $description   if defined $description;

    my $tree = _thaw_tree(
        $filename,
        $params_size + 4,
        map { $params->{$_} }
            qw( ip_version record_size merge_record_collisions ),
    );

    return $class->new(
        %{$params},
        map_key_type_callback => $callback,
        _tree                 => $tree,
    );
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

    my %types = (
        color => 'utf8_string',
        dogs  => [ 'array', 'utf8_string' ],
        size  => 'uint16',
    );

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'My-IP-Data',
        languages             => ['en'],
        description           => { en => 'My database of IP data' },
        map_key_type_callback => sub { $types{ $_[0] } },
    );

    my $network
        = Net::Works::Network->new_from_string( string => '2001:db8::/48' );

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
data with the new data. This only works if both inserts provide a hashref for
the data payload.

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

This method expects two parameters. The first is a L<Net::Works::Network>
object. The second can be any Perl data structure (except a coderef, glob, or
filehandle).

The C<$data> payload is encoded according to the L<MaxMind DB database format
spec|http://maxmind.github.io/MaxMind-DB/>. The short overview is that
anything that can be encoded in JSON can be stored in an MMDB file. It can
also handle unsigned 64-bit and 128-bit integers if they are passed as
L<Math::UInt128|Math::Int128> objects.

=head3 Insert Order, Merging, and Overwriting

Depending on whether or not you set C<merge_record_collisions> to true in the
constructor, the order in which you insert networks will affect the final tree
output.

When C<merge_record_collisions> is I<false>, the last insert "wins". This
means that if you insert C<1.2.3.255/32> and then C<1.2.3.0/24>, the data for
C<1.2.3.255/24> will overwrite the data you previously inserted for
C<1.2.3.255/232>. On the other hand, if you insert C<1.2.3.255/32> last, then
the tree will be split so that the C<1.2.3.0 - 1.2.3.254> range has different
data than C<1.2.3.255>.

In this scenario, if you want to make sure that no data is overwritten then
you need to sort your input by network prefix length.

When C<merge_record_collisions> is I<true>, then regardless of insert order,
the C<1.2.3.255/32> network will end up with its data plus the data provided
for the C<1.2.3.0/24> network, while C<1.2.3.0 - 1.2.3.254> will have the
expected data.

=head2 $tree->write_tree($fh)

Given a filehandle, this method writes the contents of the tree as a MaxMind
DB database to that filehandle.

=head2 $tree->iterate($object)

This method iterates over the tree by calling methods on the passed
object. The object must have at least one of the following three methods:
C<process_empty_record>, C<process_node_record>, C<process_data_record>.

The iteration is done in depth-first order, which means that it visits each
network in order.

Each method on the object is called with the following position parameters:

=over 4

=item

The node number as a 64-bit number.

=item

A boolean indicating whether or not this is the right or left record for the
node. True for right, false for left.

=item

The first IP number in the node's network as a 128-bit number.

=item

The prefix length for the node's network.

=item

The first IP number in the record's network as a 128-bit number.

=item

The prefix length for the record's network.

=back

If the record is a data record, the final argument will be the Perl data
structure associated with the record.

The record's network is what matches with a given data structure for data
records.

For node (and alias) records, the final argument will be the number of the
node that this record points to.

For empty records, there are no additional arguments.

=head2 $tree->freeze_tree($filename)

Given a file name, this method freezes the tree to that file. Unlike the
C<write_tree()> method, this method does write out a MaxMind DB file. Instead,
it writes out something that can be quickly thawed via the C<<
MaxMind::DB::Writer::Tree->new_from_frozen_tree >> constructor. This is useful if
you want to pass the in-memory representation of the tree between processes.

=head2 $tree->ip_version()

Returns the tree's IP version, as passed to the constructor.

=head2 $tree->record_size()

Returns the tree's record size, as passed to the constructor.

=head2 $tree->merge_record_collisions()

Returns a boolean indicating whether the tree will merge colliding records, as
determined by the constructor parameter.

=head2 $tree->map_key_type_callback()

Returns the callback used to determine the type of a map's values, as passed
to the constructor.

=head2 $tree->database_type()

Returns the tree's database type, as passed to the constructor.

=head2 $tree->languages()

Returns the tree's languages, as passed to the constructor.

=head2 $tree->description()

Returns the tree's description hashref, as passed to the constructor.

=head2 $tree->alias_ipv6_to_ipv4()

Returns a boolean indicating whether the tree will alias some IPv6 ranges to
their corresponding IPv4 ranges when the tree is written to disk.

=head2 MaxMind::DB::Writer::Tree->new_from_frozen_tree()

This method constructs a tree from a file containing a frozen tree.

This method accepts the following parameters:

=over 4

=item * filename

The filename containing the frozen tree.

This parameter is required.

=item * map_key_type_callback

This is a subroutine reference that is called in order to determine how to
store each value in a map (hash) data structure. See L<DATA TYPES> below for
more details.

This needs to be passed because subroutine references cannot be reliably
serialized and restored between processes.

This parameter is required.

=item * database_type

Override the C<<database_type>> of the frozen tree. This accepts a string of
the same form as the C<<new()>> constructor.

This parameter is optional.

=item * description

Override the C<<description>> of the frozen tree. This accepts a hashref of
the same form as the C<<new()>> constructor.

This parameter is optional.

=back

=head2 Caveat for Freeze/Thaw

The frozen tree is more or less the raw C data structures written to disk. As
such, it is very much not portable, and your ability to thaw a tree on a
machine not identical to the one on which it was written is not guaranteed.

In addition, there is no guarantee that the freeze/thaw format will be stable
across different versions of this module.

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
