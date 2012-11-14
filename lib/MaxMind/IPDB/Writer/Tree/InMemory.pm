package MaxMind::IPDB::Writer::Tree::InMemory;

use strict;
use warnings;

our $VERSION = '0.34';

use Carp qw( confess );
use Digest::MD5 qw( md5 );
use JSON::XS;
use List::Util qw( min );
use Scalar::Util qw( blessed );

use Moose;
use MooseX::StrictConstructor;

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

has _allocated_node_count  => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
);

has root_node_num => (
    is       => 'ro',
    writer   => '_set_root_node_num',
    isa      => 'Int',
    init_arg => undef,
);

has _used_node_count => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default => 0,
);

has _insert_cache => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub { {} },
);

use constant {
    LEFT  => 0,
    RIGHT => 1,
};

use constant {
    _RECORD_SIZE          => 16,
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

    my $ptr_idx = $node >> _RECORD_SIZE;

    my $byte_pos = ( $node & _NODE_POINTER_MASK ) * _NODE_SIZE;
    my $pos      = $byte_pos + $direction * _RECORD_SIZE;
    my $length   = _RECORD_SIZE;

    die "Invalid node # ($node)"
        unless defined $self->{_node_buffers}[$ptr_idx]
        && length ${ $self->{_node_buffers}[$ptr_idx] } >= $pos + $length;

    if ( !$record ) {
        return
            substr( ${ $self->{_node_buffers}[$ptr_idx] }, $pos, $length );
    }

    substr( ${ $self->{_node_buffers}[$ptr_idx] }, $pos, $length )
        = $record;

    return;
}

sub record_is_empty {
    $_[1] eq "\0" x 16;
}

sub record_pointer_value {
    return unless substr( $_[1], 4 ) eq 'POINTER_RECD';
    return unpack( N => $_[1] );
}

sub mk_pointer_record {
    return pack( NA12 => $_[1], 'POINTER_RECD' );
}

sub node_count {
    return $_[0]->_used_node_count();
}

# This turns out to be faster than using Storable.
my $Encoder = JSON::XS->new()->utf8()->allow_nonref();

sub insert_subnet {
    my $self   = shift;
    my $subnet = shift;
    my $data   = shift;

    my $key = md5( $Encoder->encode($data) );
    $self->{_data_index}{$key} ||= $data;

    my $ipnum = $subnet->first()->as_integer();

    my ( $node, $idx, $node_netmask, $bit_to_check )
        = $self->_find_cached_node($subnet);

    my $cache = $self->_insert_cache();
    $cache->{last_ipnum}   = $ipnum;
    $cache->{last_netmask} = $subnet->netmask_as_integer();

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
                $subnet,
                $node_netmask,
            );
        }

        $bit_to_check >>= 1;
    }

    $cache->{node_num_cache}[$idx] = $node;

    my $direction = $self->_direction( $ipnum, $bit_to_check );

    $self->set_record( $node, $direction, $key );

    for my $subnet ( @{ $self->{_needs_move}{subnets} } ) {
        $self->insert_subnet( $subnet, $self->{_needs_move}{data} );
    }
}

sub _find_cached_node {
    my $self   = shift;
    my $subnet = shift;

    my $ipnum   = $subnet->first()->as_integer();
    my $netmask = $subnet->netmask_as_integer();

    my $mask_length = $subnet->mask_length();
    my $default_mask = $self->_all_ones_mask($mask_length);

    my $cache = $self->_insert_cache();

    my $cached_ipnum = $cache->{last_ipnum};

    return ( $self->root_node_num(), 0, $netmask, $default_mask )
        unless $cached_ipnum;

    # Finds the position (as a count of bits) of the first 1 that is in both
    # the cached number and the number we're inserting.
    my $one_idx = index(
        sprintf(
            "%${mask_length}b",
            $cached_ipnum ^ $ipnum
        ),
        1
    );

    my $cache_idx = min(
        ( ( $one_idx >= 0 ) ? $one_idx : $mask_length - 1 ),
        $netmask - 1,
        $cache->{last_netmask} - 1
    );

    return (
        $cache->{node_num_cache}[$cache_idx] || $self->root_node_num(),
        $cache_idx,
        $netmask - $cache_idx,
        $default_mask >> $cache_idx,
    );
}

sub _direction {
    my $self         = shift;
    my $ipnum        = shift;
    my $bit_to_check = shift;

    return $bit_to_check & $ipnum ? RIGHT : LEFT;
}

sub _make_new_node {
    my $self         = shift;
    my $node         = shift;
    my $direction    = shift;
    my $record       = shift;
    my $ipnum        = shift;
    my $subnet       = shift;
    my $node_netmask = shift;

    my $new_node   = $self->_next_node_num;
    my $new_record = $self->mk_pointer_record($new_node);
    $self->set_record( $node, $direction, $new_record );

    unless ( $self->record_is_empty($record) ) {
        $self->{_needs_move}{subnets} = $self->_split_node(
            $ipnum,
            $subnet->netmask_as_integer(),
            $node_netmask,
            $subnet->version()
        );

        $self->{_needs_move}{data} = $self->{_data_index}{$record};
    }

    return $new_node;
}

sub _split_node {
    my $self           = shift;
    my $start_ipnum    = shift;
    my $subnet_netmask = shift;
    my $node_netmask   = shift;
    my $version        = shift;

    my $bits = $version == 6 ? do { use bigint; 128 } : 32;

    my $t = ~0 << ( $bits - $subnet_netmask + $node_netmask );
    my $old_start_ipnum = $start_ipnum & $t;
    my $old_end_ipnum   = ~$t + $old_start_ipnum;
    my $end_ipnum = $start_ipnum | ~( ~0 << ( $bits - $subnet_netmask ) );

    my @subnets;
    if ( $old_start_ipnum < $start_ipnum ) {
        @subnets = MM::Net::Subnet->range_as_subnets(
            MM::Net::IPAddress->new_from_integer(
                integer => $old_start_ipnum,
                version => $version,
            ),
            MM::Net::IPAddress->new_from_integer(
                integer => $start_ipnum - 1,
                version => $version,
            )
        );
    }

    if ( $old_end_ipnum > $end_ipnum ) {
        push @subnets,
            MM::Net::Subnet->range_as_subnets(
            MM::Net::IPAddress->new_from_integer(
                integer => $end_ipnum + 1,
                version => $version,
            ),
            MM::Net::IPAddress->new_from_integer(
                integer => $old_end_ipnum,
                version => $version,
            ),
            );
    }

    return \@subnets;
}

sub iterate {
    my $self = shift;
    my $cb   = shift;

    my $ip_integer = 0;

    no warnings 'recursion';
    my $iterator;
    $iterator = sub {
        my $node_num = shift;

        for my $dir ( LEFT, RIGHT ) {
            my $value = $self->get_record( $node_num, $dir );

            if ( my $pointer = $self->record_pointer_value($value) ) {
                $cb->(
                    $node_num, $dir,
                    pointer => $pointer,
                );

                $iterator->($pointer);
            }
            elsif ( $self->record_is_empty($value) ) {
                $cb->(
                    $node_num, $dir,
                    is_empty => 1,
                );
            }
            else {
                $cb->(
                    $node_num, $dir,
                    key   => $value,
                    value => $self->{_data_index}{$value},
                );
            }
        }
    };

    $iterator->( $self->root_node_num() );

    return;
}

# XXX - for testing only - eventually this may go away once the internals are
# cleaned up and there are better tests of the internals.
sub lookup_ip_address {
    my $self    = shift;
    my $address = shift;

    my $num = $address->as_integer();

    my $mask = $self->_all_ones_mask( $address->mask_length() );

    my $node = $self->root_node_num();

    while ($mask) {
        my $side = $mask & $num ? RIGHT : LEFT;
        my $record = $self->get_record( $node, $side );

        return undef if $self->record_is_empty($record);

        unless ( $node = $self->record_pointer_value($record) ) {
            confess 'Found a terminal record that is not in our data store'
                unless exists $self->{_data_index}{$record};

            return $self->{_data_index}{$record};
        }

        $mask >>= 1;
    }
}

sub _all_ones_mask {
    my $self = shift;
    my $bits = shift;

    return 2**31 if $bits == 32;

    use bigint;
    return 2**127;
}

__PACKAGE__->meta()->make_immutable();

1;
