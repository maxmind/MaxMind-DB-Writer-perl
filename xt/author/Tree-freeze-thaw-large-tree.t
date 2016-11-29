use strict;
use warnings;
use utf8;
use autodie;

use lib 't/lib';

use Test::Requires {
    JSON                  => 0,
    'MaxMind::DB::Reader' => 0.040000,
};

use Test::MaxMind::DB::Writer qw( test_freeze_thaw );
use Test::More;

use File::Temp qw( tempdir );
use JSON;
use Math::Int128 qw( uint128 );
use MaxMind::DB::Reader;
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

my $json_file = 't/test-data/GeoLite2-Country.json';
unless ( -f $json_file ) {
    diag(<<"EOF");

In order to run this test you need to create a JSON dump of a GeoLite2 Country
database. You can do this with the mmdb-dump-database script that ships with
MaxMind::DB::Reader. Note that this script doesn't generate 100% correct JSON,
so you'll need to trim off the trailing comma it leaves in on the last record
of the array.

Save this JSON file to $json_file

We don't include this file in the repo since it ends up being around 650MB in
size.

EOF
    plan skip_all => "This test requires the $json_file file";
}

my @languages = qw(
    de
    en
    es
    fr
    ja
    pt-BR
    ru
    zh-CN
);

my %type_map = (
    city                  => 'map',
    continent             => 'map',
    country               => 'map',
    geoname_id            => 'uint32',
    is_anonymous_proxy    => 'boolean',
    is_satellite_provider => 'boolean',
    latitude              => 'double',
    location              => 'map',
    longitude             => 'double',
    metro_code            => 'uint16',
    names                 => 'map',
    postal                => 'map',
    registered_country    => 'map',
    represented_country   => 'map',
    subdivisions          => [ 'array', 'map' ],
    traits                => 'map',
);

my $map_key_type_callback = sub { $type_map{ $_[0] } // 'utf8_string' };

my $tree = MaxMind::DB::Writer::Tree->new(
    ip_version              => 6,
    record_size             => 32,
    database_type           => 'Test-GeoLite2-Country',
    languages               => \@languages,
    description             => { en => 'Test GeoLite2 Country' },
    merge_record_collisions => 1,
    alias_ipv6_to_ipv4      => 1,
    map_key_type_callback   => $map_key_type_callback,
);

open my $fh, '<', $json_file or die $!;
my $geolite2_data = do { local $/ = undef; <$fh> };
my $geolite_data = JSON->new->decode($geolite2_data);
close $fh or die $!;

my $i = 0;
for my $geolite_entry ( @{$geolite_data} ) {
    my ($network) = keys %{$geolite_entry};
    $tree->insert_network(
        Net::Works::Network->new_from_string( string => $network ),
        $geolite_entry->{$network},
    );

    $i++;
    diag("Inserted $i records") unless $i % 100_000;
}

test_freeze_thaw($tree);

my $dir = tempdir( CLEANUP => 1 );
my $frozen_file = "$dir/Test-GeoLite2-Country.frozen";
$tree->freeze_tree($frozen_file);

my $mmdb_file = "$dir/Test-GeoLite2-Country.mmdb";

if ( my $pid = fork ) {
    waitpid $pid, 0 or die $!;
}
else {
    my $thawed_tree = MaxMind::DB::Writer::Tree->new_from_frozen_tree(
        filename              => $frozen_file,
        map_key_type_callback => $map_key_type_callback,
    );

    open $fh, '>', $mmdb_file or die $!;
    $thawed_tree->write_tree($fh);
    close $fh or die $!;

    exit 0;
}

my $reader = MaxMind::DB::Reader->new( file => $mmdb_file );

for my $i ( 0 .. int( ( scalar @{$geolite_data} ) / 777 ) ) {
    my $geolite_entry = $geolite_data->[ $i * 777 ];
    my ($network)     = keys %{$geolite_entry};
    my $ip            = $network =~ s{/.+$}{}r;

    is_deeply(
        $reader->record_for_address($ip),
        $geolite_entry->{$network},
        "record for $ip"
    );
}

done_testing();
