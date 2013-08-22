package MaxMind::DB::Writer::Tree::InMemory;

use strict;
use warnings;

use Carp qw( confess );
use Digest::MD5 qw( md5 );
use List::Util qw( min );
use Math::Int128 0.06 qw( uint128 );
use MaxMind::DB::Common qw( LEFT_RECORD RIGHT_RECORD );
use MaxMind::DB::Writer::Tree::Processor::NodeCounter;
use Net::Works 0.11;
use Net::Works::Network;
use Scalar::Util qw( blessed );
use Sereal::Encoder;

use Moose;
use MooseX::StrictConstructor;

has ip_version => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

# We intentionally access most of these attributes by calling $self->{...}
# rather than using accessors, but declaring them makes it easy to provide a
# default and provides a little bit of documentation on their types.
has _data_index => (
    is       => 'ro',
    isa      => 'HashRef[Any]',
    init_arg => undef,
    default  => sub { {} },
);

has _node_buffers => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    init_arg => undef,
    default  => sub { [] },
);

has _allocated_node_count => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
);

has _root_node_num => (
    is       => 'ro',
    writer   => '_set_root_node_num',
    isa      => 'Int',
    init_arg => undef,
);

has _used_node_count => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
);

has _deleted_node_count => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
);

has _insert_cache => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub { {} },
);

use constant {
    _RECORD_SIZE          => 17,
    _NODES_PER_ALLOCATION => 2**16,
};

use constant {
    _NODE_POINTER_MASK => _NODES_PER_ALLOCATION - 1,
    _NODE_SIZE         => _RECORD_SIZE * 2,
};

sub BUILD {
    my $self = shift;

    $self->_set_root_node_num( $self->_next_node_num() );

    return;
}

sub _allocate_more_nodes {
    my $self = shift;

    my $new_nodes = "\0" x ( _NODES_PER_ALLOCATION * _NODE_SIZE );
    push @{ $self->{_node_buffers} }, \$new_nodes;
    $self->{_allocated_node_count} += _NODES_PER_ALLOCATION;
}

sub _next_node_num {
    my $self = shift;

    $self->_allocate_more_nodes()
        unless $self->{_used_node_count} < $self->{_allocated_node_count};

    return $self->{_used_node_count}++;
}

sub get_record {
    my $self = shift;

    confess "2 args required" if @_ != 2;
    return $self->_record(@_);
}

sub set_record {
    my $self = shift;

    confess "3 args required" if @_ != 3;
    return $self->_record(@_);
}

sub _record {
    my $self      = shift;
    my $node      = shift;
    my $direction = shift;
    my $record    = shift;

    # This is equivalent to $node / 2**16 (and has nothing to do with the
    # record size).
    my $ptr_idx = $node >> 16;

    my $byte_pos = ( $node & _NODE_POINTER_MASK ) * _NODE_SIZE;
    my $pos      = $byte_pos + $direction * _RECORD_SIZE;
    my $length   = _RECORD_SIZE;

    die "Invalid node # ($node)"
        unless defined $self->{_node_buffers}[$ptr_idx]
        && length ${ $self->{_node_buffers}[$ptr_idx] } >= $pos + $length;

    if ( !$record ) {
        return substr( ${ $self->{_node_buffers}[$ptr_idx] }, $pos, $length );
    }

    substr( ${ $self->{_node_buffers}[$ptr_idx] }, $pos, $length ) = $record;

    return;
}

{
    my $empty = "\0" x _RECORD_SIZE;

    sub record_is_empty {
        $_[1] eq $empty;
    }
}

sub record_pointer_value {
    return unless index( $_[1], 'P' ) == 0;
    return unpack( N => substr( $_[1], 1, 4 ) );
}

{
    my $filler = "\0" x 12;

    sub mk_pointer_record {
        return 'P' . pack( N => $_[1] ) . $filler;
    }
}

sub node_count {
    return $_[0]->_used_node_count() - $_[0]->_deleted_node_count();
}

{
    my $Encoder = Sereal::Encoder->new( { sort_keys => 1 } );

    sub insert_subnet {
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

        my $key = 'D' . md5( $Encoder->encode($data) );
        $self->{_data_index}{$key} ||= $data;

        $self->_insert_subnet( $subnet, $key );

        return;
    }
}

sub insert_subnet_as_alias {
    my $self    = shift;
    my $subnet  = shift;
    my $pointer = shift;

    my $node_count = $self->node_count();

    my $final_node = $self->_insert_subnet( $subnet, "\0" x _RECORD_SIZE );

    my $last_bit_in_subnet
        = $subnet->first_as_integer() & ( 1 << $subnet->mask_length() );

    # If the last bit of the subnet is a one then the alias only applies to
    # the right record in the tree. This can be verified visually by looking
    # at a visualization of an aliased tree.
    if ($last_bit_in_subnet) {
        $self->set_record(
            $final_node, RIGHT_RECORD,
            $self->get_record( $pointer, LEFT_RECORD )
        );
    }
    else {
        $self->set_record(
            $final_node, LEFT_RECORD,
            $self->get_record( $pointer, LEFT_RECORD )
        );
    }

    return $self->node_count() - $node_count;
}

sub _insert_subnet {
    my $self         = shift;
    my $subnet       = shift;
    my $final_record = shift;

    my $ipnum = $subnet->first_as_integer();

    my ( $node, $idx, $node_netmask, $bit_to_check )
        = $self->_find_cached_node($subnet);

    my $cache = $self->_insert_cache();
    $cache->{last_ipnum}   = $ipnum;
    $cache->{last_netmask} = $subnet->mask_length();

    local $self->{_needs_move} = {};

    while ( --$node_netmask ) {
        $cache->{node_num_cache}[ $idx++ ] = $node;

        my $direction = $self->_direction( $ipnum, $bit_to_check );

        my $record = $self->get_record( $node, $direction );

        if ( my $next_node = $self->record_pointer_value($record) ) {
            $node = $next_node;
        }
        else {
            $node = $self->_make_new_node(
                $node,
                $direction,
                $record,
                $ipnum,
                $node_netmask,
                $subnet,
            );
        }

        $bit_to_check >>= 1;
    }

    $cache->{node_num_cache}[$idx] = $node;

    my $direction = $self->_direction( $ipnum, $bit_to_check );

    if ($final_record eq $self->get_record( $node, ( $direction + 1 ) % 2 )) {
        my $parent_subnet = Net::Works::Network->new_from_integer(
            integer     => $subnet->first_as_integer,
            mask_length => $subnet->mask_length - 1,
        );
        $self->_insert_subnet( $parent_subnet, $final_record );
        return $node;
    }

    my $existing = $self->get_record( $node, $direction );

    # This happens when we insert a subnet that is bigger than an earlier
    # subnet - for example we first insert 1.1.2.255/32 and then insert
    # 1.1.2.254/31 - the latter overwrites the former, so we are effectively
    # deleting nodes from the tree.
    if ( my $pointer = $self->record_pointer_value($existing) ) {

        # We have to subtract one if we are going to merge this node so that
        # we don't double count it as we move up the tree
        $self->{_deleted_node_count}
            += $self->_node_count_starting_at($pointer);
    }
    $self->set_record( $node, $direction, $final_record );

    for my $subnet ( @{ $self->{_needs_move}{subnets} } ) {
        $self->insert_subnet( $subnet, $self->{_needs_move}{data} );
    }

    return $node;
}

sub _find_cached_node {
    my $self   = shift;
    my $subnet = shift;

    my $netmask = $subnet->mask_length();

    my $bits         = $subnet->bits();
    my $default_mask = $self->_mask_for_leftmost_bit();

    my $cache = $self->_insert_cache();

    my $cached_ipnum = $cache->{last_ipnum};

    return ( $self->_root_node_num(), 0, $netmask, $default_mask )
        if $ENV{MAXMIND_DB_WRITER_NO_CACHE} || !$cached_ipnum;

    my $one_idx = $self->_first_shared_bit(
        $subnet->first_as_integer(),
        $cached_ipnum,
        $bits,
    );

    my $cache_idx = min(
        ( ( $one_idx >= 0 ) ? $one_idx : $bits - 1 ),
        $netmask - 1,
        $cache->{last_netmask} - 1
    );

    return (
        $cache->{node_num_cache}[$cache_idx] || $self->_root_node_num(),
        $cache_idx,
        $netmask - $cache_idx,
        $default_mask >> $cache_idx,
    );
}

# Finds the position (as a count of bits) of the first 1 that is in both the
# cached number and the number we're inserting.
sub _first_shared_bit {
    my $self   = shift;
    my $ipnum1 = shift;
    my $ipnum2 = shift;
    my $bits   = shift;

    # This is hack that we do instead of right shifting the $xor_ipnum value
    # one bit at a time until we find the last 1 bit. Doing it that way is
    # fairly slow since it involves an overloaded Math::Int128 operation for
    # each shift. This is about 3.5x as fast as the right shift approach.
    my $xor_string = join q{}, map { sprintf( '%08b', ord($_) ) } split //,
        Math::Int128::int128_to_net( $ipnum1 ^ $ipnum2 );

    my $idx = index( $xor_string, '1' );
    return $idx >= 0 ? $bits - ( 127 - $idx ) - 1 : $bits - 1;
}

sub _mask_for_leftmost_bit {
    my $self = shift;

    return $self->ip_version() == 4
        ? 2**31
        : uint128('170141183460469231731687303715884105728');
}

sub _direction {
    my $self         = shift;
    my $ipnum        = shift;
    my $bit_to_check = shift;

    return $bit_to_check & $ipnum ? RIGHT_RECORD : LEFT_RECORD;
}

sub _make_new_node {
    my $self             = shift;
    my $parent_node      = shift;
    my $parent_direction = shift;
    my $parent_record    = shift;
    my $ipnum            = shift;
    my $node_netmask     = shift;
    my $subnet           = shift;

    my $new_node   = $self->_next_node_num;
    my $new_record = $self->mk_pointer_record($new_node);
    $self->set_record( $parent_node, $parent_direction, $new_record );

    unless ( $self->record_is_empty($parent_record) ) {
        $self->{_needs_move}{subnets} = $self->_split_node(
            $ipnum,
            $node_netmask,
            $subnet,
        );

        $self->{_needs_move}{data} = $self->{_data_index}{$parent_record};
    }

    return $new_node;
}

sub _split_node {
    my $self         = shift;
    my $start_ipnum  = shift;
    my $node_netmask = shift;
    my $subnet       = shift;

    my $version        = $subnet->version();
    my $subnet_netmask = $subnet->mask_length();
    my $bits           = $subnet->bits();

    my $t = ~uint128(0) << ( $bits - $subnet_netmask + $node_netmask );
    my $old_start_ipnum = $start_ipnum & $t;
    my $old_end_ipnum   = ~$t + $old_start_ipnum;
    my $end_ipnum
        = $start_ipnum | ~( ~uint128(0) << ( $bits - $subnet_netmask ) );

    my @subnets;
    if ( $old_start_ipnum < $start_ipnum ) {
        @subnets = Net::Works::Network->range_as_subnets(
            Net::Works::Address->new_from_integer(
                integer => $old_start_ipnum,
                version => $version,
            ),
            Net::Works::Address->new_from_integer(
                integer => $start_ipnum - 1,
                version => $version,
            )
        );
    }

    if ( $old_end_ipnum > $end_ipnum ) {
        push @subnets,
            Net::Works::Network->range_as_subnets(
            Net::Works::Address->new_from_integer(
                integer => $end_ipnum + 1,
                version => $version,
            ),
            Net::Works::Address->new_from_integer(
                integer => $old_end_ipnum,
                version => $version,
            ),
            );
    }

    return \@subnets;
}

sub iterate {
    my $self              = shift;
    my $object            = shift;
    my $starting_node_num = shift || $self->_root_node_num();

    my $ip_integer = 0;

    my $iterator = $self->_make_iterator($object);

    $iterator->($starting_node_num);

    return;
}

sub _make_iterator {
    my $self   = shift;
    my $object = shift;

    my $max_netmask = $self->{_saw_ipv6} ? uint128(128) : 32;

    my $iterator;
    $iterator = sub {
        no warnings 'recursion';
        my $node_num = shift;
        my $ip_num   = shift || 0;
        my $netmask  = shift || 1;

        my @directions = $object->directions_for_node($node_num);

        my %records
            = map { $_ => $self->get_record( $node_num, $_ ) } @directions;

        return
            unless $object->process_node(
            $node_num,
            \%records,
            $ip_num,
            $netmask,
            );

        for my $dir (@directions) {
            my $value = $records{$dir};

            my $next_ip_num
                = $dir
                ? $ip_num + ( 2**( $max_netmask - $netmask ) )
                : $ip_num;

            if ( my $pointer = $self->record_pointer_value($value) ) {
                return
                    unless $object->process_pointer_record(
                    $node_num,
                    $dir,
                    $pointer,
                    $ip_num,
                    $netmask,
                    $next_ip_num,
                    $netmask + 1
                    );

                $iterator->( $pointer, $next_ip_num, $netmask + 1 );
            }
            elsif ( $self->record_is_empty($value) ) {
                return
                    unless $object->process_empty_record(
                    $node_num,
                    $dir,
                    $ip_num,
                    $netmask,
                    );
            }
            else {
                return
                    unless $object->process_value_record(
                    $node_num,
                    $dir,
                    $value,
                    $self->{_data_index}{$value},
                    $ip_num,
                    $netmask,
                    );
            }
        }
    };

    return $iterator;
}

# XXX - this method is only used for testing, but it's useful to have
sub lookup_ip_address {
    my $self    = shift;
    my $address = shift;

    require MaxMind::DB::Writer::Tree::Processor::LookupIPAddress;

    my $processor
        = MaxMind::DB::Writer::Tree::Processor::LookupIPAddress->new(
        ip_address => $address );

    $self->iterate($processor);

    return $processor->value();
}

sub node_num_for_subnet {
    my $self   = shift;
    my $subnet = shift;

    my ( $node_num, $dir ) = $self->pointer_record_for_subnet($subnet);

    return $self->record_pointer_value(
        $self->get_record( $node_num, $dir ) );
}

sub pointer_record_for_subnet {
    my $self   = shift;
    my $subnet = shift;

    require MaxMind::DB::Writer::Tree::Processor::RecordForSubnet;

    my $processor
        = MaxMind::DB::Writer::Tree::Processor::RecordForSubnet->new(
        subnet => $subnet );

    $self->iterate($processor);

    return @{ $processor->record() };
}

sub write_svg_image {
    my $self = shift;
    my $file = shift;

    require MaxMind::DB::Writer::Tree::Processor::VisualizeTree;

    my $processor
        = MaxMind::DB::Writer::Tree::Processor::VisualizeTree->new(
        ip_version => $self->{_saw_ipv6} ? 6 : 4 );

    $self->iterate($processor);

    $processor->graph()->run( output_file => $file );

    return;
}

# This is really only useful for debugging problems with the tree's
# self-reported node count.
sub _real_node_count {
    my $self = shift;

    return $self->_node_count_starting_at(0);
}

sub _node_count_starting_at {
    my $self          = shift;
    my $starting_node = shift;

    my $processor = MaxMind::DB::Writer::Tree::Processor::NodeCounter->new();

    $self->iterate( $processor, $starting_node );

    return $processor->node_count();
}

__PACKAGE__->meta()->make_immutable();

1;
