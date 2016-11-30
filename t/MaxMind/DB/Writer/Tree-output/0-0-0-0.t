use strict;
use warnings;

use Test::More;

use Test::Requires (
    'MaxMind::DB::Reader' => 0.040000,
);

use MaxMind::DB::Writer::Tree;

use File::Temp qw( tempdir );
use MaxMind::DB::Reader;
use Net::Works::Network;

my $tempdir = tempdir( CLEANUP => 1 );

{
    my $filename = _write_tree();

    my $reader = MaxMind::DB::Reader->new( file => $filename );

    for my $address (qw( 0.0.0.0 0.0.0.1 0.0.0.255 )) {
        is_deeply(
            $reader->record_for_address($address),
            {
                ip => '0.0.0.0',
            },
            "got expected data for $address"
        );
    }
}

done_testing();

sub _write_tree {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 4,
        record_size   => 24,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        map_key_type_callback    => sub { 'utf8_string' },
        remove_reserved_networks => 0
    );

    my $subnet = Net::Works::Network->new_from_string(
        string  => '0.0.0.0/24',
        version => 4,
    );

    $tree->insert_network(
        $subnet,
        { ip => '0.0.0.0' },
    );

    my $filename = $tempdir . '/Test-0-network.mmdb';
    open my $fh, '>', $filename or die $!;
    $tree->write_tree($fh);
    close $fh or die $!;

    return $filename;
}
