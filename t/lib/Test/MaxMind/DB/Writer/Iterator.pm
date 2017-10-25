package Test::MaxMind::DB::Writer::Iterator;

use strict;
use warnings;

use Net::Works::Network ();

sub new {
    my $class      = shift;
    my $ip_version = shift;

    return bless { ip_version => $ip_version }, $class;
}

## no critic (Subroutines::ProhibitManyArgs)
sub process_node_record {
    my $self               = shift;
    my $node_num           = shift;
    my $dir                = shift;
    my $node_ip_num        = shift;
    my $node_prefix_length = shift;

    $self->_saw_network( $node_ip_num, $node_prefix_length, 'node' );

    $self->_saw_record( $node_num, $dir );

    push @{ $self->{node_records} },
        $self->_nw_network( $node_ip_num, $node_prefix_length );

    return;
}

sub process_empty_record {
    my $self               = shift;
    my $node_num           = shift;
    my $dir                = shift;
    my $node_ip_num        = shift;
    my $node_prefix_length = shift;

    $self->_saw_network( $node_ip_num, $node_prefix_length, 'empty' );

    $self->_saw_record( $node_num, $dir );

    return;
}

sub process_data_record {
    my $self                 = shift;
    my $node_num             = shift;
    my $dir                  = shift;
    my $node_ip_num          = shift;
    my $node_prefix_length   = shift;
    my $record_ip_num        = shift;
    my $record_prefix_length = shift;
    my $value                = shift;

    $self->_saw_network( $node_ip_num, $node_prefix_length, 'data' );

    $self->_saw_record( $node_num, $dir );

    push @{ $self->{data_records} },
        [
        $self->_nw_network( $record_ip_num, $record_prefix_length ),
        $value,
        ];

    return;
}

sub _saw_network {
    my $self          = shift;
    my $ip_num        = shift;
    my $prefix_length = shift;

    my $network = $self->_nw_network( $ip_num, $prefix_length );

    $self->{networks}{ $network->as_string() }++;
}

sub _saw_record {
    my $self     = shift;
    my $node_num = shift;
    my $dir      = shift;

    $self->{records}{"$node_num-$dir"}++;

    return;
}

sub _nw_network {
    my $self          = shift;
    my $ip_num        = shift;
    my $prefix_length = shift;

    return Net::Works::Network->new_from_integer(
        integer       => $ip_num,
        prefix_length => $prefix_length,
        version       => $self->{ip_version},
    );
}

1;
