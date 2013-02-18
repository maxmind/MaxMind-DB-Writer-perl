package MaxMind::IPDB::Writer::Tree::Processor::LookupIPAddress;

use strict;
use warnings;

use Moose;

has ip_address => (
    is       => 'ro',
    isa      => 'Net::Works::Address',
    required => 1,
);

has _ip_address_bits => (
    is       => 'ro',
    isa      => 'ArrayRef[Bool]',
    init_arg => undef,
    lazy     => 1,
    default  => sub { [ split //, $_[0]->ip_address()->as_bit_string() ] },
);

has value => (
    is       => 'rw',
    writer   => '_set_value',
    init_arg => undef,
);

sub directions_for_node {
    my $self = shift;

    die q{Exhausted all bits in the IP address but we haven't found a terminal node}
        unless @{ $self->_ip_address_bits() };

    return shift @{ $self->_ip_address_bits() };
}

sub process_node {
    return 1;
}

sub process_pointer_record {
    return 1;
}

sub process_empty_record {
    return 0;
}

sub process_value_record {
    my $self = shift;
    shift; # $node_num
    shift; # $dir
    shift; # record value

    $self->_set_value(shift);

    return 0;
}

__PACKAGE__->meta()->make_immutable();

1;
