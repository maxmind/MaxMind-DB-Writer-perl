use strict;
use warnings;
use autodie;

use Test::More;

use File::Temp qw( tempdir );
use MaxMind::IPDB::Writer::Tree::InMemory;
use MaxMind::IPDB::Writer::Tree::File;
use MM::Net::Subnet;

use MaxMind::IPDB::Reader::File;

my $tempdir = tempdir( CLEANUP => 1 );

{
    my @subnets = MM::Net::Subnet->range_as_subnets( '1.1.1.1', '1.1.1.32' );

    my ( $tree, $filename ) = _write_tree( \@subnets, { ip_version => 4 } );

    my $reader = MaxMind::IPDB::Reader::File->new( file => $filename );

    _test_metadata( $reader, $tree, { ip_version => 4 } );

    for my $ip ( map { $_->first()->as_string() } @subnets ) {
        is_deeply(
            $reader->data_for_address($ip),
            { ip => $ip },
            "found expected data record for $ip"
        );
    }

    for my $pair (
        [ '1.1.1.3'  => '1.1.1.2' ],
        [ '1.1.1.5'  => '1.1.1.4' ],
        [ '1.1.1.7'  => '1.1.1.4' ],
        [ '1.1.1.9'  => '1.1.1.8' ],
        [ '1.1.1.15' => '1.1.1.8' ],
        [ '1.1.1.17' => '1.1.1.16' ],
        [ '1.1.1.31' => '1.1.1.16' ],
        ) {

        my ( $ip, $expect ) = @{$pair};
        is_deeply(
            $reader->data_for_address($ip),
            { ip => $expect },
            "found expected data record for $ip"
        );
    }

    for my $ip ( '1.1.1.33', '255.254.253.123' ) {
        is(
            $reader->data_for_address($ip),
            undef,
            "no data found for $ip"
        );
    }
}

{
    my @subnets = MM::Net::Subnet->range_as_subnets(
        '::1:ffff:ffff',
        '::2:0000:0059'
    );

    my ( $tree, $filename ) = _write_tree( \@subnets, { ip_version => 6 } );

    my $reader = MaxMind::IPDB::Reader::File->new( file => $filename );

    _test_metadata( $reader, $tree, { ip_version => 6 } );

    for my $ip ( map { $_->first()->as_string() } @subnets ) {
        is_deeply(
            $reader->data_for_address($ip),
            { ip => $ip },
            "found expected data record for $ip"
        );
    }

    for my $pair (
        [ '::2:0:1'  => '::2:0:0' ],
        [ '::2:0:33' => '::2:0:0' ],
        [ '::2:0:39' => '::2:0:0' ],
        [ '::2:0:41' => '::2:0:40' ],
        [ '::2:0:49' => '::2:0:40' ],
        [ '::2:0:52' => '::2:0:50' ],
        [ '::2:0:57' => '::2:0:50' ],
        [ '::2:0:59' => '::2:0:58' ],
        ) {

        my ( $ip, $expect ) = @{$pair};
        is_deeply(
            $reader->data_for_address($ip),
            { ip => $expect },
            "found expected data record for $ip"
        );
    }

    for my $ip ( '1.1.1.33', '255.254.253.123', '89fa::' ) {
        is(
            $reader->data_for_address($ip),
            undef,
            "no data found for $ip"
        );
    }
}

done_testing();

sub _write_tree {
    my $subnets  = shift;
    my $metadata = shift;

    my $tree = MaxMind::IPDB::Writer::Tree::InMemory->new();

    for my $subnet ( @{$subnets} ) {
        $tree->insert_subnet(
            $subnet,
            { ip => $subnet->first()->as_string() }
        );
    }

    my $writer = MaxMind::IPDB::Writer::Tree::File->new(
        tree => $tree,
        _standard_metadata(),
        %{$metadata},
    );

    my $filename = $tempdir . "/Test-IPv$metadata->{ip_version}.mmipdb";
    open my $fh, '>', $filename;

    $writer->write_tree($fh);

    return ( $tree, $filename );
}

sub _standard_metadata {
    return (
        record_size   => 24,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
    );
}

sub _test_metadata {
    my $reader          = shift;
    my $tree            = shift;
    my $expect_metadata = shift;

    my $desc = 'IPv' . $expect_metadata->{ip_version};

    my $metadata = $reader->metadata();
    my %expect   = (
        binary_format_major_version => 2,
        binary_format_minor_version => 0,
        ip_version                  => 6,
        _standard_metadata(),
        %{$expect_metadata},
    );

    for my $key ( sort keys %expect ) {
        is_deeply(
            $metadata->$key(),
            $expect{$key},
            "read expected value for metadata key $key - $desc"
        );
    }

    like(
        $metadata->build_epoch(),
        qr/^\d+$/,
        "build_epoch is an integer - $desc"
    );

    cmp_ok(
        $metadata->build_epoch(),
        '<=',
        time(),
        "build_epoch is <= the current timestamp - $desc"
    );

    is(
        $metadata->node_count(),
        $tree->node_count(),
        "metadata node_count matches value from in-memory tree - $desc"
    );
}
