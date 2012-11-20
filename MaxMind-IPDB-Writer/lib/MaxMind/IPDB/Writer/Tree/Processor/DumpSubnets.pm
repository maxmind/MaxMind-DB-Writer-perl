package MaxMind::IPDB::Writer::Tree::Processor::DumpSubnets;

use strict;
use warnings;

use MaxMind::IPDB::Common qw( LEFT_RECORD RIGHT_RECORD );

use Moose;

has ip_version => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

sub directions_for_node {
    return ( LEFT_RECORD, RIGHT_RECORD );
}

sub process_node {
    my $self = shift;
    shift;
    shift;
    my $ip_num  = shift;
    my $netmask = shift;

    warn $self->_subnet( $ip_num, $netmask )->as_string(), "\n";

    return 1;
}

sub process_pointer_record {
    return 1;
}

sub process_empty_record {
    my $self = shift;
    shift;
    shift;
    my $ip_num  = shift;
    my $netmask = shift;

    warn $self->_subnet( $ip_num, $netmask )->as_string, " = <null>\n";

    return 1;
}

sub process_value_record {
    my $self = shift;
    shift;
    shift;
    shift;
    shift;
    my $ip_num  = shift;
    my $netmask = shift;

    warn $self->_subnet( $ip_num, $netmask )->as_string, " = something\n";

    return 1;
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
