use strict;
use warnings;

use Test::More;

use MaxMind::DB::Writer::Tree;

use File::Temp qw( tempdir );
use Net::Works::Address;
use Net::Works::Network;
use Test::Fatal qw( exception );

my $tempdir = tempdir( CLEANUP => 1 );

{
    my %tests = (
        '::1.1.1.1'        => { subnet => '::1.1.1.1/128' },
        '::1.1.1.2'        => { subnet => '::1.1.1.2/127' },
        '::255.255.255.2'  => { subnet => '::255.255.255.0/120' },
        '::fffe:0:0'       => { subnet => '::fffe:0:0/96' },
        '::fffe:9:a'       => { subnet => '::fffe:0:0/96' },
        '::ffff:ff02'      => { subnet => '::255.255.255.0/120' },
        '::1.1.1.3'        => { subnet => '::1.1.1.2/127' },
        '::ffff:101:101'   => { subnet => '::1.1.1.1/128' },
        '::ffff:1.1.1.2'   => { subnet => '::1.1.1.2/127' },
        '::ffff:101:103'   => { subnet => '::1.1.1.2/127' },
        '::ffff:ffff:ff02' => { subnet => '::255.255.255.0/120' },
        '2001:0:101:101::' => { subnet => '::1.1.1.1/128' },
        '2001:0:101:102::' => { subnet => '::1.1.1.2/127' },
        '2001:0:101:103::' => { subnet => '::1.1.1.2/127' },
        '2002:101:101::'   => { subnet => '::1.1.1.1/128' },
        '2002:101:102::'   => { subnet => '::1.1.1.2/127' },
        '2002:101:103::'   => { subnet => '::1.1.1.2/127' },
        '2002:ffff:ff02::' => { subnet => '::255.255.255.0/120' },
        '2004::'           => { subnet => '2004::/96' },
        '2004::9:a'        => { subnet => '2004::/96' },
    );

    my $tree = _write_tree();

    for my $address ( sort keys %tests ) {
        is_deeply(
            $tree->lookup_ip_address(
                Net::Works::Address->new_from_string(
                    string => $address, version => 6
                )
            ),
            $tests{$address},
            "got expected data for $address"
        );
    }

    # Aliases should never be overwritten. Currently we just throw an
    # exception is someone tries to overwrite one. In the future, we could do
    # something smarter, _but_ it isn't clear what the right behavior is.
    like(
        exception { $tree->insert_network( '2001::/32', {} ) },
        qr/Attempted to overwrite an alised network./,
        'received expected error when trying to overwrite an alias node'
    );

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
        alias_ipv6_to_ipv4    => 1,
        map_key_type_callback => sub { 'utf8_string' },
    );

    # Note: we don't want all of the alias nodes (::ffff:0.0.0.0 and 2002::)
    # to have adjacent nodes with data, as we want to make sure that the
    # merging of empty nodes does not merge the alias nodes.
    my @subnets = map {
        Net::Works::Network->new_from_string( string => $_, version => 6 )
        } qw(
        ::1.1.1.1/128
        ::1.1.1.2/127
        ::255.255.255.0/120
        ::fffe:0:0/96
        2004::/96
    );

    for my $net (@subnets) {
        $tree->insert_network(
            $net,
            { subnet => $net->as_string() },
        );
    }

    return $tree;
}
