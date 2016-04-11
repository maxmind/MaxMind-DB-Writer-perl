use strict;
use warnings;

use Test::Fatal;
use Test::More;

use File::Temp qw( tempdir );
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

use Test::Requires {
    'MaxMind::DB::Reader' => 0.040000,
};

my $tempdir = tempdir( CLEANUP => 1 );

# make a frozen tree on disk with record size 24
{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 4,
        record_size   => 24,
        database_type => 'Test',
        languages     => ['en'],
        description   => {
            en => 'Test Database',
        },
        map_key_type_callback => sub { },
    );

    $tree->insert_network(
        Net::Works::Network->new_from_string( string => '1.64.22.0/24', ),
        { answer => 42 },
    );

    $tree->insert_network(
        Net::Works::Network->new_from_string( string => '1.64.23.0/24', ),
        { ncc => 1701 },
    );

    $tree->freeze_tree("$tempdir/frozen");
}

# unfreeze the tree setting network size to 32, write it as an mmdb
{
    my $tree = MaxMind::DB::Writer::Tree->new_from_frozen_tree(
        filename              => "$tempdir/frozen",
        map_key_type_callback => sub { 'uint32' },
        record_size           => 32,
    );

    open my $fh, '>:raw', "$tempdir/mmdb";
    $tree->write_tree($fh);
}

# load the mmdb, check record size is 32 not 24
{
    ## no critic (Modules::RequireExplicitInclusion)
    my $mmdb = MaxMind::DB::Reader->new( file => "$tempdir/mmdb" );
    ## use critic
    my $metadata = $mmdb->metadata;

    is( $metadata->record_size, 32, 'record size' );

    # check that we can still read those IPs correctly
    is_deeply(
        $mmdb->record_for_address('1.64.22.123'),
        { answer => 42 },
        'ip address lookup check 1/2'
    );
    is_deeply(
        $mmdb->record_for_address('1.64.23.123'),
        { ncc => 1701 },
        'ip address lookup check 2/2'
    );
}

done_testing();

