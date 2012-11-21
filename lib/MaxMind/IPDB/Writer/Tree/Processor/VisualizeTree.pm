package MaxMind::IPDB::Writer::Tree::Processor::VisualizeTree;

use strict;
use warnings;

use Data::Dumper::Concise;
use GraphViz2;
use MaxMind::IPDB::Common qw( LEFT_RECORD RIGHT_RECORD );

use Moose;

has ip_version => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has graph => (
    is       => 'ro',
    isa      => 'GraphViz2',
    init_arg => undef,
    default  => sub { GraphViz2->new( global => { directed => 1 } ) },
);

has _seen_nodes => (
    is       => 'ro',
    traits   => ['Hash'],
    init_arg => undef,
    default  => sub { {} },
    handles  => {
        _seen_node => 'get',
        _saw_node  => 'set',
    },
);

has _labels => (
    is       => 'ro',
    isa      => 'HashRef[Str]',
    init_arg => undef,
    default  => sub { {} },
);

sub directions_for_node {
    my $self = shift;

    return ( LEFT_RECORD, RIGHT_RECORD );
}

sub process_node {
    my $self     = shift;
    my $node_num = shift;
    shift;
    my $ip_num   = shift;
    my $netmask  = shift;

    return 0 if $self->_seen_node($node_num);

    $self->_saw_node( $node_num, 1 );

    return 1;
}

sub process_pointer_record {
    my $self             = shift;
    my $node_num         = shift;
    my $dir              = shift;
    my $pointer_node_num = shift;
    my $current_ip_num   = shift;
    my $current_netmask  = shift;
    my $pointer_ip_num   = shift;
    my $pointer_netmask  = shift;

    $self->graph()->add_edge(
        from => $self->_label_for_node(
            $node_num, $current_ip_num, $current_netmask
        ),
        to => $self->_label_for_node(
            $pointer_node_num, $pointer_ip_num, $pointer_netmask
        ),
        label => ( $dir ? 'RIGHT' : 'LEFT' ),
    );

    return 1;
}

sub process_empty_record {
    my $self     = shift;
    my $node_num = shift;
    my $dir      = shift;

    return 1;
}

sub process_value_record {
    my $self     = shift;
    my $node_num = shift;
    my $dir      = shift;
    shift;
    my $value   = shift;
    my $ip_num  = shift;
    my $netmask = shift;

    $self->graph()->add_edge(
        from  => $self->_label_for_node( $node_num, $ip_num, $netmask ),
        to    => quotemeta( Dumper($value) ),
        label => ( $dir ? 'RIGHT' : 'LEFT' ),
    );

    return 1;
}

sub _label_for_node {
    my $self     = shift;
    my $node_num = shift;
    my $ip_num   = shift;
    my $netmask  = shift;

    my $labels = $self->_labels();

    return $labels->{$node_num} //= "IPDB $node_num - "
        . $self->_subnet( $ip_num, $netmask )->as_string();
}

sub _subnet {
    my $self    = shift;
    my $ip_num  = shift;
    my $netmask = shift;

    my $address = MM::Net::IPAddress->new_from_integer(
        integer => $ip_num,
        version => $self->ip_version(),
    );

    return MM::Net::Subnet->new( subnet => $address . '/' . $netmask );
}

__PACKAGE__->meta()->make_immutable();

1;
