use strict;
use warnings;

use Test::More;

use Test::Requires (
    'MaxMind::DB::Verifier' => 0,
);

use File::Temp qw( tempdir );
use MaxMind::DB::Metadata;
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

my $tempdir = tempdir( CLEANUP => 1 );

for my $record_size ( 24, 28, 32 ) {
    my $file = "$tempdir/IPv4-$record_size.mmdb",;

    _write_tree(
        $record_size,
        [ Net::Works::Network->range_as_subnets( '1.1.1.1', '1.1.1.32' ) ],
        {
            ip_version => 4,
        },
        $file,
    );

    my $desc = "IPv4 - $record_size-bit record";
    _verify( $file, $desc );
}

for my $record_size ( 24, 28, 32 ) {
    for my $should_alias ( 0, 1 ) {
        my $file
            = "$tempdir/IPv6-$record_size-alias-$should_alias.mmdb";

        _write_tree(
            $record_size,
            [
                Net::Works::Network->range_as_subnets(
                    '::1.1.1.1', '::1.1.1.32'
                ),
                Net::Works::Network->range_as_subnets(
                    '2003::', '2003::FFFF'
                )
            ],
            {
                ip_version         => 6,
                alias_ipv6_to_ipv4 => $should_alias,
            },
            $file,
        );

        my $desc
            = "IPv6 - $record_size-bit record - alias: $should_alias";
        _verify( $file, $desc );
    }
}

done_testing();

sub _write_tree {
    my $record_size = shift;
    my $subnets     = shift;
    my $metadata    = shift;
    my $file        = shift;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => $metadata->{ip_version},
        record_size   => $record_size,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        %{$metadata},
        map_key_type_callback => sub { 'utf8_string' },
    );

    for my $subnet ( @{$subnets} ) {
        $tree->insert_network(
            $subnet,
            { ip => $subnet->first()->as_string() }
        );
    }

    open my $fh, '>:raw', $file;

    $tree->write_tree($fh);

    return;
}

sub _verify {
    my $file = shift;
    my $desc = shift;

    my $verifier = MaxMind::DB::Verifier->new(
        file  => $file,
        quiet => 1,
    );

    ok(
        $verifier->verify(),
        "verifier says the database file is valid - $desc"
    );
}
