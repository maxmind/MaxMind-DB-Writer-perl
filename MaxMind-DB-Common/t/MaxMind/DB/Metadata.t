use strict;
use warnings;

use Test::More;

use MaxMind::DB::Metadata;

my $metadata = MaxMind::DB::Metadata->new(
    binary_format_major_version => 1,
    binary_format_minor_version => 1,
    build_epoch                 => time(),
    database_type               => 'Test',
    description                 => { foo => 'bar' },
    ip_version                  => 4,
    node_count                  => 100,
    record_size                 => 32,
);

ok( $metadata, 'code compiles' );

done_testing();
