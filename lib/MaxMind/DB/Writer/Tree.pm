package MaxMind::DB::Writer::Tree;

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

sub _build_node_count {
    my $self = shift;

    return $self->_node_count( $self->_tree() );
}

sub iterate {
    my $self   = shift;
    my $object = shift;

    my $ip_integer = 0;

    my $iterator = $self->_make_iterator($object);

    $iterator->();

    return;
}

sub _make_iterator {
    my $self   = shift;
    my $object = shift;

    my $max_netmask = $self->ip_version() == 6 ? uint128(128) : 32;

    my $iterator;
    $iterator = sub {
        no warnings 'recursion';
        my $node_num = shift;
        my $ip_num   = shift || 0;
        my $netmask  = shift || 1;

        my @directions = $object->directions_for_node($node_num);

        my %records
            = map { $_ => $self->get_record( $node_num, $_ ) } @directions;

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

sub DEMOLISH {
    my $self = shift;

    $self->_free_tree( $self->_tree() )
        if $self->_has_tree();

    return;
}

__PACKAGE__->meta()->make_immutable();

1;
