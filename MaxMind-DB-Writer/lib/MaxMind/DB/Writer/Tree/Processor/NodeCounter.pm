package MaxMind::DB::Writer::Tree::Processor::NodeCounter;

use strict;
use warnings;

use MaxMind::DB::Common qw( LEFT_RECORD RIGHT_RECORD );

use Moose;

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

sub directions_for_node {
    my $self = shift;

    return ( LEFT_RECORD, RIGHT_RECORD );
}

sub process_node {
    my $self     = shift;
    my $node_num = shift;

    return 0 if $self->_seen_node($node_num);

    $self->_saw_node( $node_num => 1 );
}

sub process_pointer_record {
    return 1;
}

sub process_empty_record {
    return 1;
}

sub process_value_record {
    return 1;
}

sub node_count {
    my $self = shift;

    return scalar keys %{ $self->_seen_nodes() };
}

__PACKAGE__->meta()->make_immutable();

1;
