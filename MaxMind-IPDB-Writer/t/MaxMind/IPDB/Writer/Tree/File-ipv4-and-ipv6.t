use strict;
use warnings;

use Test::More;

use MaxMind::IPDB::Writer::Tree::InMemory;
use MaxMind::IPDB::Writer::Tree::File;

use File::Temp qw( tempdir );
use MaxMind::IPDB::Reader::File;
use Net::Works::Network;

my $tempdir = tempdir( CLEANUP => 1 );

{
    my ( $tree, $filename ) = _write_tree();

    my $reader = MaxMind::IPDB::Reader::File->new( file => $filename );

    my %tests = (
        '1.1.1.1'          => { subnet => '::1.1.1.1/128' },
        '::1.1.1.1'        => { subnet => '::1.1.1.1/128' },
        '1.1.1.2'          => { subnet => '::1.1.1.2/127' },
        '::1.1.1.2'        => { subnet => '::1.1.1.2/127' },
        '1.1.1.3'          => { subnet => '::1.1.1.2/127' },
        '255.255.255.2'    => { subnet => '::255.255.255.0/120' },
        '::fffe:0:0'       => { subnet => '::fffe:0:0/96' },
        '::fffe:9:a'       => { subnet => '::fffe:0:0/96' },
        '::ffff:ff02'      => { subnet => '::255.255.255.0/120' },
        '::1.1.1.3'        => { subnet => '::1.1.1.2/127' },
        '::ffff:101:101'   => { subnet => '::1.1.1.1/128' },
        '::ffff:1.1.1.2'   => { subnet => '::1.1.1.2/127' },
        '::ffff:101:103'   => { subnet => '::1.1.1.2/127' },
        '::ffff:ffff:ff02' => { subnet => '::255.255.255.0/120' },
        '2002:101:101::'   => { subnet => '::1.1.1.1/128' },
        '2002:101:102::'   => { subnet => '::1.1.1.2/127' },
        '2002:101:103::'   => { subnet => '::1.1.1.2/127' },
        '2002:ffff:ff02::' => { subnet => '::255.255.255.0/120' },
        '2003::'           => { subnet => '2003::/96' },
        '2003::9:a'        => { subnet => '2003::/96' },
    );

    for my $address ( sort keys %tests ) {
        is_deeply(
            $reader->data_for_address($address),
            $tests{$address},
            "got expected data for $address"
        );
    }
}

done_testing();

sub _write_tree {
    my $tree = MaxMind::IPDB::Writer::Tree::InMemory->new();

    my @subnets
        = map { Net::Works::Network->new( subnet => $_, version => 6 ) }
        qw(
        ::1.1.1.1/128
        ::1.1.1.2/127
        ::255.255.255.0/120
        ::fffe:0:0/96
        2003::/96
    );

    for my $net (@subnets) {
        $tree->insert_subnet(
            $net,
            { subnet => $net->as_string() },
        );
    }

    my $writer = MaxMind::IPDB::Writer::Tree::File->new(
        tree          => $tree,
        record_size   => 24,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        ip_version            => 6,
        alias_ipv6_to_ipv4    => 1,
        map_key_type_callback => sub { 'utf8_string' },
    );

    my $filename = $tempdir . "/Test-ipv6-alias.mmipdb";
    open my $fh, '>', $filename;

    $writer->write_tree($fh);

    return ( $tree, $filename );
}
