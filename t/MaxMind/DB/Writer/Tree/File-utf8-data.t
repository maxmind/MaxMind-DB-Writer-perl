use strict;
use warnings;

use Test::More;

use Test::Requires (
    'MaxMind::DB::Reader' => 0.040000,
);

use MaxMind::DB::Writer::Tree::InMemory;
use MaxMind::DB::Writer::Tree::File;

use Encode ();
use File::Temp qw( tempdir );
use Net::Works::Network;

{
    my $tb = Test::Builder->new();

    binmode $_, ':encoding(UTF-8)'
        for $tb->output(),
        $tb->failure_output(),
        $tb->todo_output();
}

my $tempdir = tempdir( CLEANUP => 1 );

my $utf8_string = "\x{4eba}";

{
    my $filename = _write_tree();

    my $reader = MaxMind::DB::Reader->new( file => $filename );

    for my $address (qw( 1.2.3.0 1.2.3.128 1.2.3.255 )) {
        is_deeply(
            $reader->record_for_address($address),
            {
                subnet => '1.2.3.0/24',
                string => $utf8_string,
            },
            "got expected data for $address"
        );
    }

    my $string = $reader->record_for_address('1.2.3.0')->{string};

    ok(
        Encode::is_utf8($string),
        "string from lookup ($string) is marked as utf8"
    );
}

done_testing();

sub _write_tree {
    my $tree = MaxMind::DB::Writer::Tree::InMemory->new( ip_version => 4 );

    my $subnet = Net::Works::Network->new_from_string(
        string  => '1.2.3.0/24',
        version => 4,
    );

    $tree->insert_subnet(
        $subnet,
        {
            subnet => $subnet->as_string(),
            string => $utf8_string,
        },
    );

    my $writer = MaxMind::DB::Writer::Tree::File->new(
        tree          => $tree,
        record_size   => 24,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        ip_version            => 4,
        map_key_type_callback => sub { 'utf8_string' },
    );

    my $filename = $tempdir . "/Test-utf8-string.mmdb";
    open my $fh, '>', $filename;

    $writer->write_tree($fh);

    return $filename;
}
