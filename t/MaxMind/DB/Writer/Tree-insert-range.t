use strict;
use warnings;

use lib 't/lib';

use MaxMind::DB::Writer::Tree;
use Test::More;

subtest 'IPv6 test start_ip == end_ip insert' => sub {
    my $tree = _make_tree(6);
    my $ip   = '2001:4860:4860::8888';

    _test_ranges(
        $tree,
        [ [ $ip, $ip ] ],
        {},
        [ '2001:4860:4860::8887', '2001:4860:4860::8889' ]
    );
};

subtest 'IPv6 complicated ranges' => sub {
    my $tree = _make_tree(6);

    my $data = { start_ip => '2001:4860:4860::1' };
    _test_ranges(
        $tree,
        [ [ '2001:4860:4860::1', '2001:4860:4860::FFFE' ] ],
        {
            '2001:4860:4860::1'    => $data,
            '2001:4860:4860::2'    => $data,
            '2001:4860:4860::4'    => $data,
            '2001:4860:4860::8'    => $data,
            '2001:4860:4860::10'   => $data,
            '2001:4860:4860::20'   => $data,
            '2001:4860:4860::40'   => $data,
            '2001:4860:4860::80'   => $data,
            '2001:4860:4860::100'  => $data,
            '2001:4860:4860::200'  => $data,
            '2001:4860:4860::400'  => $data,
            '2001:4860:4860::800'  => $data,
            '2001:4860:4860::1000' => $data,
            '2001:4860:4860::2000' => $data,
            '2001:4860:4860::4000' => $data,
            '2001:4860:4860::8000' => $data,
        },
        [ '2001:4860:4860::', '2001:4860:4860::FFFF' ]
    );
};

subtest 'IPv4 range in IPv6 tree' => sub {
    my $tree = _make_tree(6);

    my $data = { start_ip => '1.0.0.1' };
    _test_ranges(
        $tree,
        [ [ '1.0.0.1', '1.0.0.2' ] ],
        {},
        [ '1.0.0.0', '1.0.0.3' ]
    );
};

subtest 'IPv4 test start_ip == end_ip insert' => sub {
    my $tree = _make_tree(4);
    my $ip   = '1.1.1.1';

    _test_ranges(
        $tree,
        [ [ $ip, $ip ] ],
        {},
        [ '1.1.1.0', '1.1.1.2' ]
    );
};

subtest 'IPv4 complicated ranges' => sub {
    my $tree = _make_tree(4);

    my $data = { start_ip => '1.0.0.1' };
    _test_ranges(
        $tree,
        [ [ '1.0.0.1', '1.0.0.255' ] ],
        {
            '1.0.0.2'   => $data,
            '1.0.0.4'   => $data,
            '1.0.0.8'   => $data,
            '1.0.0.16'  => $data,
            '1.0.0.32'  => $data,
            '1.0.0.64'  => $data,
            '1.0.0.128' => $data,
        },
        [ '1.0.0.0', '1.0.1.0' ]
    );
};

subtest 'IPv4 overlapping ranges' => sub {
    my $tree = _make_tree(4);

    my $data_1 = { start_ip => '1.0.0.1' };
    my $data_3 = { start_ip => '1.0.0.3' };
    _test_ranges(
        $tree,
        [
            [ '1.0.0.1', '1.0.0.10' ],
            [ '1.0.0.3', '1.0.0.4' ]
        ],
        {
            (
                map { $_ => $data_1 } (
                    '1.0.0.1', '1.0.0.2', '1.0.0.5', '1.0.0.6', '1.0.0.7',
                    '1.0.0.8', '1.0.0.9', '1.0.0.10'
                )
            ),
            ( map { $_ => $data_3 } ( '1.0.0.3', '1.0.0.4' ) ),

        },
        [ '1.0.0.0', '1.0.0.11' ],
        0
    );
};

{
    my @empty_ipv4_addresses = qw(
        0.0.0.0
        0.0.0.255
        10.0.0.0
        10.0.0.255
        100.64.0.0
        127.0.0.0
        169.254.0.0
        172.16.0.0
        192.0.0.0
        192.0.2.0
        192.88.99.0
        192.168.0.0
        198.18.0.0
        198.51.100.0
        203.0.113.0
        224.0.0.0
        240.0.0.0
        255.255.255.255
    );

    subtest 'IPv4 remove reserved networks' => sub {
        my $tree = _make_tree(4);

        my $data_0   = { start_ip => '0.0.0.0' };
        my $data_128 = { start_ip => '128.0.0.0' };

        _test_ranges(
            $tree,
            [
                [ '0.0.0.0', '127.255.255.255' ],

                # XXX - We are inserting this as two separate ranges due to
                # https://github.com/maxmind/MaxMind-DB-Writer-perl/issues/55
                [ '128.0.0.0', '255.255.255.255' ],
            ],
            {
                (
                    map { $_ => $data_0 }
                        ( '1.0.0.0', '126.0.2.255', '11.1.1.11' )
                ),
                (
                    map { $_ => $data_128 }
                        ( '128.101.101.101', '193.0.0.4', )
                )
            },
            \@empty_ipv4_addresses,
            0
        );

    };

    subtest 'IPv6 remove reserved networks' => sub {
        my $tree = _make_tree(6);

        my $data_0    = { start_ip => '::' };
        my $data_8000 = { start_ip => '8000::' };

        _test_ranges(
            $tree,
            [
                [ '::', '7FFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF' ],

                # XXX - We are inserting this as two separate ranges due to
                # https://github.com/maxmind/MaxMind-DB-Writer-perl/issues/55
                [ '8000::', 'FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF' ],
            ],
            {
                (
                    map { $_ => $data_0 } (
                        '1.0.0.0', '126.0.2.255', '11.1.1.11', '193.0.0.4',
                        '2002::',
                    )
                ),
                (
                    map { $_ => $data_8000 } ( '8000::',, 'a000::', 'efff::' )
                )
            },
            [
                @empty_ipv4_addresses,
                '100::',
                '2001::',
                '2001:db8::',
                'fc00::',
                'fe80::',
                'ff00::',
            ],
            0
        );

    };

}
done_testing();

sub _make_tree {
    my $ip_version = shift;
    my %args       = @_;

    return MaxMind::DB::Writer::Tree->new(
        ip_version            => $ip_version,
        record_size           => 24,
        database_type         => 'Test',
        languages             => ['en'],
        description           => { en => 'Test tree' },
        map_key_type_callback => sub { },
    );
}

sub _test_ranges {
    my $tree           = shift;
    my @insert_ranges  = @{ shift() };
    my %expected       = %{ shift() };
    my @unexpected_ips = @{ shift() };
    my $test_endpoints = shift // 1;

    for my $range (@insert_ranges) {
        my ( $start_ip, $end_ip ) = @{$range};
        my $data = { start_ip => $start_ip };
        $tree->insert_range( $start_ip, $end_ip, { start_ip => $start_ip } );
        @expected{ $start_ip, $end_ip } = ($data) x 2 if $test_endpoints;
    }

    $tree->_maybe_remove_reserved_networks;

    for my $ip ( sort keys %expected ) {
        is_deeply(
            $tree->lookup_ip_address($ip), $expected{$ip},
            "expected data for $ip"
        );
    }

    for my $ip (@unexpected_ips) {
        my $data = $tree->lookup_ip_address($ip);
        is( $data, undef, "no data for $ip" ) or diag explain $data;
    }
}
