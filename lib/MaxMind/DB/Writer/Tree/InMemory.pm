package MaxMind::DB::Writer::Tree::InMemory;

use strict;
use warnings;

use Carp qw( confess );
use List::Util qw( min );
use Math::Int128 0.06 qw( uint128 );
use MaxMind::DB::Common qw( LEFT_RECORD RIGHT_RECORD );
use MaxMind::DB::Writer::Tree::Processor::NodeCounter;
use Net::Works 0.13;
use Net::Works::Network;
use Scalar::Util qw( blessed );
use Sereal::Encoder;

use Moose;
use MooseX::StrictConstructor;

use XSLoader;

XSLoader::load(
    __PACKAGE__,
    exists $MaxMind::DB::Writer::Tree::InMemory::{VERSION}
        && ${ $MaxMind::DB::Writer::Tree::InMemory::{VERSION} }
    ? ${ $MaxMind::DB::Writer::Tree::InMemory::{VERSION} }
    : '42'
);

has ip_version => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has _tree => (
    is        => 'ro',
    init_arg  => undef,
    lazy      => 1,
    builder   => '_build_mmdb',
    predicate => '_has_mmdb',
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

    return $self->_new_tree( $self->ip_version() );
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

sub DEMOLISH {
    my $self = shift;

    $self->_free_tree( $self->_tree() )
        if $self->_has_tree();

    return;
}

__PACKAGE__->meta()->make_immutable();

1;
