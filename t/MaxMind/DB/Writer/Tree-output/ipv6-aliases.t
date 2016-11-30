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

    my %tests = (
        '1.1.1.1'            => { subnet => '::1.1.1.1/128' },
        '::1.1.1.1'          => { subnet => '::1.1.1.1/128' },
        '1.1.1.2'            => { subnet => '::1.1.1.2/127' },
        '::1.1.1.2'          => { subnet => '::1.1.1.2/127' },
        '1.1.1.3'            => { subnet => '::1.1.1.2/127' },
        '223.255.255.2'      => { subnet => '::223.255.255.0/120' },
        '::fffe:0:0'         => { subnet => '::fffe:0:0/96' },
        '::fffe:9:a'         => { subnet => '::fffe:0:0/96' },
        '::dfff:ff02'        => { subnet => '::223.255.255.0/120' },
        '::1.1.1.3'          => { subnet => '::1.1.1.2/127' },
        '::ffff:101:101'     => { subnet => '::1.1.1.1/128' },
        '::ffff:1.1.1.2'     => { subnet => '::1.1.1.2/127' },
        '::ffff:101:103'     => { subnet => '::1.1.1.2/127' },
        '::ffff:dfff:ff02'   => { subnet => '::223.255.255.0/120' },
        '2001:0:101:101::'   => { subnet => '::1.1.1.1/128' },
        '2001:0:101:102::'   => { subnet => '::1.1.1.2/127' },
        '2001:0:101:103::'   => { subnet => '::1.1.1.2/127' },
        '2001:0:dfff:ff02::' => { subnet => '::223.255.255.0/120' },
        '2002:101:101::'     => { subnet => '::1.1.1.1/128' },
        '2002:101:102::'     => { subnet => '::1.1.1.2/127' },
        '2002:101:103::'     => { subnet => '::1.1.1.2/127' },
        '2002:dfff:ff02::'   => { subnet => '::223.255.255.0/120' },
        '2004::'             => { subnet => '2004::/96' },
        '2004::9:a'          => { subnet => '2004::/96' },
    );

    for my $address ( sort keys %tests ) {
        is_deeply(
            $reader->record_for_address($address),
            $tests{$address},
            "got expected data for $address"
        );
    }
}

done_testing();

sub _write_tree {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 6,
        record_size   => 24,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        alias_ipv6_to_ipv4       => 1,
        map_key_type_callback    => sub { 'utf8_string' },
        remove_reserved_networks => 1,
    );

    # Note: we don't want all of the alias nodes (::ffff:0.0.0.0 and 2002::)
    # to have adjacent nodes with data, as we want to make sure that the
    # merging of empty nodes does not merge the alias nodes.
    my @subnets = qw(
        ::1.1.1.1/128
        ::1.1.1.2/127
        ::223.255.255.0/120
        ::fffe:0:0/96
        2004::/96
    );

    for my $net (@subnets) {
        $tree->insert_network(
            $net,
            { subnet => $net },
        );
    }

    my $filename = $tempdir . '/Test-ipv6-alias.mmdb';
    open my $fh, '>', $filename or die $!;
    $tree->write_tree($fh);
    close $fh or die $!;

    return $filename;
}
