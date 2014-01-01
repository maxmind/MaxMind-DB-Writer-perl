package Test::MaxMind::DB::Writer;

use strict;
use warnings;

use Test::More;

use MaxMind::DB::Writer::Tree;
use Net::Works::Address;
use Net::Works::Network;

use Exporter qw( import );
our @EXPORT_OK = qw( make_tree_from_pairs ranges_to_data test_tree );

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
        ip_version    => $pairs->[0][0]->version(),
        record_size   => 24,
        database_type => 'Test',
        languages     => ['en'],
        description   => { en => 'Test tree' },
        %{ $args || {} },
    );

    for my $pair ( @{$pairs} ) {
        my ( $subnet, $data ) = @{$pair};

        $tree->insert_network( $subnet, $data );
    }

    return $tree;
}

sub _test_expected_data {
    my $tree   = shift;
    my $expect = shift;
    my $desc   = shift;

    foreach my $pair ( @{$expect} ) {
        my ( $subnet, $data ) = @{$pair};

        my $iter = $subnet->iterator();
        while ( my $address = $iter->() ) {
            is_deeply(
                $tree->lookup_ip_address($address),
                $data,
                "Got expected data for $address - $desc"
            );
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
        for my $subnet (
            map { Net::Works::Network->range_as_subnets( @{$_} ), }
            @{$insert_ranges} ) {

            my $data = {
                x  => 'foo',
                id => $id,
            };

            push @insert, [ $subnet, $data ];

            my $iter = $subnet->iterator();
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

1;
