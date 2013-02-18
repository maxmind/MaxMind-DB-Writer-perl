package MaxMind::DB::Writer::Tree::Processor::RecordForSubnet;

use strict;
use warnings;

use Moose;

has subnet => (
    is       => 'ro',
    isa      => 'Net::Works::Network',
    required => 1,
);

has _ip_address_bits => (
    is       => 'ro',
    isa      => 'ArrayRef[Bool]',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_ip_address_bits',
);

has record => (
    is       => 'rw',
    writer   => '_set_record',
    init_arg => undef,
);

sub directions_for_node {
    my $self = shift;

    return shift @{ $self->_ip_address_bits() };
}

sub process_node {
    return 1;
}

sub process_pointer_record {
    my $self     = shift;
    my $node_num = shift;
    my $dir      = shift;

    return 1 if @{ $self->_ip_address_bits() };

    $self->_set_record( [ $node_num, $dir ] );

    return 0;
}

sub process_empty_record {
    my $self = shift;

    die 'Hit an empty record before we reached the beginning of the '
        . $self->subnet()->as_string()
        . ' subnet';
}

sub process_value_record {
    my $self = shift;

    die 'Hit a value record before we reached the beginning of the '
        . $self->subnet()->as_string()
        . ' subnet';
}

sub _build_ip_address_bits {
    my $self = shift;

    my @bits = ( split //, $self->subnet()->first()->as_bit_string() )
        [ 0 .. $self->subnet()->mask_length() - 1 ];

    # We don't need to look at the last bit. We're looking for the record that
    # points _to_ this subnet, not the record that represents the subnet
    # itself.
    pop @bits;

    return \@bits;
}

__PACKAGE__->meta()->make_immutable();

1;
