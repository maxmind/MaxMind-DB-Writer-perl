use strict;
use warnings;

use Test::More;

use File::Temp qw( tempdir );
use MaxMind::DB::Metadata;
use MaxMind::DB::Verifier;
use MaxMind::DB::Writer::Tree::InMemory;
use MaxMind::DB::Writer::Tree::File;

my $tempdir = tempdir( CLEANUP => 1 );

for my $record_size ( 24, 28, 32 ) {
    my $file = "$dir/IPv4-$record_size.mmdb",;

    _write_tree(
        $record_size,
        [
            Net::Works::Network->range_as_subnets(
                '1.1.1.1', '1.1.1.32'
            )
        ],
        { ip_version => 4 },
        $file,
    );

    my $desc = "IPv4 - $record_size-bit record";

    my $verifier = MaxMind::DB::Verifier->new(
        file  => $file,
        quiet => 1,
    );

    ok(
        $verifier->verify(),
        "verifier says the database file is valid - $desc"
    );
}

done_testing();

sub _write_tree {
    my $record_size = shift;
    my $subnets     = shift;
    my $metadata    = shift;
    my $file = shift;

    my $tree = MaxMind::DB::Writer::Tree::InMemory->new();

    for my $subnet ( @{$subnets} ) {
        $tree->insert_subnet(
            $subnet,
            { ip => $subnet->first()->as_string() }
        );
    }

    my $writer = MaxMind::DB::Writer::Tree::File->new(
        tree          => $tree,
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

    open my $fh, '>:raw', $file;

    $writer->write_tree($fh);

    return;
}
