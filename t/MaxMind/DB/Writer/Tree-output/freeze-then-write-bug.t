use strict;
use warnings;

use Test::Fatal;
use Test::More;

use File::Temp qw( tempdir );
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;

my $tempdir = tempdir( CLEANUP => 1 );

# The underlying bug was happening because calling freeze_tree() would call
# finalize_tree() internally. Then when write_tree() was called, it would
# create IP6->4 alias nodes in the tree, but because the tree though it was
# finalized, these new nodes would never get numbered.
{
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 6,
        record_size   => 24,
        database_type => 'Test',
        languages     => ['en'],
        description   => {
            en => 'Test Database',
        },

        # This bug only manifests when this is true
        alias_ipv6_to_ipv4    => 1,
        root_data_type        => 'utf8_string',
        map_key_type_callback => sub { },
    );

    $tree->insert_network(
        Net::Works::Network->new_from_string( string => '::1.64.22.0/120', ),
        'foo',
    );

    $tree->freeze_tree("$tempdir/frozen");

    my $output;
    open my $fh, '>:raw', \$output;
    is(
        exception { $tree->write_tree($fh) },
        undef,
        'no exception writing tree where an alias overwrote an existing record'
    );
}

done_testing();

__DATA__

