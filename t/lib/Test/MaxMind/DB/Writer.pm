package Test::MaxMind::DB::Writer;

use strict;
use warnings;

use Test::More;

use Data::Printer;
use List::Util qw( all );
use MaxMind::DB::Writer::Tree;
use Net::Works::Address;
use Net::Works::Network;
use Scalar::Util qw( blessed );

use Exporter qw( import );
our @EXPORT_OK
    = qw( make_tree_from_pairs ranges_to_data test_iterator_sanity test_tree );

sub test_tree {
    my $insert_pairs = shift;
    my $expect_pairs = shift;
    my $desc         = shift;
    my $args         = shift;

    my $tree = make_tree_from_pairs( $insert_pairs, $args );

    _test_expected_data( $tree, $expect_pairs, $desc );

    for my $raw (qw( 1.1.1.33 8.9.10.11 ffff::1 )) {
        my $address = Net::Works::Address->new_from_string(
            string  => $raw,
            version => ( $raw =~ /::/ ? 6 : 4 ),
        );

        is(
            $tree->lookup_ip_address($address),
            undef,
            "The address $address is not in the tree - $desc"
        );
    }
}

sub make_tree_from_pairs {
    my $pairs = shift;
    my $args  = shift;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version => ( $pairs->[0][0] =~ /::/ ? 6 : 4 ),
        record_size   => 24,
        database_type => 'Test',
        languages     => ['en'],
        description   => { en => 'Test tree' },
        %{ $args || {} },
    );

    for my $pair ( @{$pairs} ) {
        my ( $network, $data ) = @{$pair};
        $network = Net::Works::Network->new_from_string( string => $network )
            unless blessed $network;

        $tree->insert_network( $network, $data );
    }

    return $tree;
}

sub _test_expected_data {
    my $tree   = shift;
    my $expect = shift;
    my $desc   = shift;

    foreach my $pair ( @{$expect} ) {
        my ( $network, $data ) = @{$pair};

        my $iter = $network->iterator();
        while ( my $address = $iter->() ) {
            my $result = $tree->lookup_ip_address($address);
            is_deeply(
                $tree->lookup_ip_address($address),
                $data,
                "Got expected data for $address - $desc"
            ) or diag p $result;
        }
    }
}

{
    # We want to have a unique id as part of the data for various tests
    my $id = 0;

    sub ranges_to_data {
        my $insert_ranges = shift;
        my $expect_ranges = shift;

        my %ip_to_data;
        my @insert;
        for my $network (
            map { Net::Works::Network->range_as_subnets( @{$_} ), }
            @{$insert_ranges} ) {

            my $data = {
                x  => 'foo',
                id => $id,
            };

            push @insert, [ $network, $data ];

            my $iter = $network->iterator();
            while ( my $ip = $iter->() ) {
                $ip_to_data{ $ip->as_string() } = $data;
            }

            $id++;
        }

        my @expect = (
            map { [ $_, $ip_to_data{ $_->first()->as_string() } ] } (
                map { Net::Works::Network->range_as_subnets( @{$_} ), }
                    @{$expect_ranges}
            )
        );

        return \@insert, \@expect;
    }
}

sub test_iterator_sanity {
    my $iterator      = shift;
    my $tree          = shift;
    my $network_count = shift;
    my $desc          = shift;

    ok(
        ( all { $_ == 1 } values %{ $iterator->{nodes} } ),
        "each node was visited exactly once - $desc"
    );

    ok(
        ( all { $_ == 1 } values %{ $iterator->{records} } ),
        "each record was visited exactly once - $desc"
    );

    ok(
        ( all { $_ == 2 } values %{ $iterator->{networks} } ),
        "each network was visited exactly twice (two records per node) - $desc"
    );

    is(
        scalar values %{ $iterator->{records} },
        $tree->node_count() * 2,
        "saw every record for every node in the tree - $desc"
    );

    my @data_networks = map { $_->[0] } @{ $iterator->{data_records} };
    is(
        scalar @data_networks,
        $network_count,
        "saw $network_count networks - $desc"
    );

    is_deeply(
        [ map { $_->as_string() } @data_networks ],
        [ map { $_->as_string() } sort @data_networks ],
        "data nodes are seen in network order when iterating - $desc"
    );

    my %first_ips;
    for my $network (@data_networks) {
        $first_ips{ $network->first()->as_string }++;
    }

    ok(
        ( all { $_ == 1 } values %first_ips ),
        "did not see two data records with the same network first IP address - $desc"
    );
}

1;
