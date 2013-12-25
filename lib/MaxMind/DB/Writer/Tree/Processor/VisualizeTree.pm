package MaxMind::DB::Writer::Tree::Processor::VisualizeTree;

use strict;
use warnings;

use Data::Dumper::Concise;
use GraphViz2;

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

has _labels => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { {} },
);

sub process_node_record {
    my $self            = shift;
    my $node_num        = shift;
    my $dir             = shift;
    my $current_ip_num  = shift;
    my $current_netmask = shift;
    my $next_ip_num     = shift;
    my $next_netmask    = shift;
    my $next_node_num   = shift;

    $self->graph()->add_edge(
        from => $self->_label_for_node(
            $node_num, $current_ip_num, $current_netmask
        ),
        to => $self->_label_for_node(
            $next_node_num, $next_ip_num, $next_netmask
        ),
        label => ( $dir ? 'RIGHT' : 'LEFT' ),
    );

    return 1;
}

sub process_empty_record {
    return;
}

sub process_data_record {
    my $self            = shift;
    my $node_num        = shift;
    my $dir             = shift;
    my $current_ip_num  = shift;
    my $current_netmask = shift;
    my $next_ip_num     = shift;
    my $next_netmask    = shift;
    my $value           = shift;

    $self->graph()->add_edge(
        from => $self->_label_for_node( $node_num, $current_ip_num, $current_netmask ),
        to => $self->_network( $next_ip_num, $next_netmask ) . ' = '
            . quotemeta( Dumper($value) ),
        label => ( $dir ? 'RIGHT' : 'LEFT' ),
    );

    return 1;
}

sub _label_for_node {
    my $self     = shift;
    my $node_num = shift;
    my $ip_num   = shift;
    my $netmask  = shift;

    my $network = $self->_network( $ip_num, $netmask );

    return $self->_labels()->{$node_num} //=
          "Node $node_num - "
        . $network->as_string() . ' ('
        . $network->first()->as_string . ' - '
        . $network->last()->as_string() . ')';
}

sub _network {
    my $self    = shift;
    my $ip_num  = shift;
    my $netmask = shift;

    return Net::Works::Network->new_from_integer(
        integer     => $ip_num,
        mask_length => $netmask,
        version     => $self->ip_version(),
    );
}

__PACKAGE__->meta()->make_immutable();

1;
