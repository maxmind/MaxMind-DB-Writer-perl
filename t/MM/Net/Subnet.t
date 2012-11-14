use strict;
use warnings;

use Test::More;

use MM::Net::Subnet;

{
    my $net = MM::Net::Subnet->new( subnet => '1.1.1.0/28' );

    is(
        $net->as_string(),
        '1.1.1.0/28',
        'as_string returns value passed to the constructor'
    );

    is(
        $net->netmask_as_integer(),
        28,
        'netmask is 28'
    );

    my $first = $net->first();
    isa_ok(
        $first,
        'MM::Net::IPAddress',
        'return value of ->first'
    );

    is(
        $first->as_string(),
        '1.1.1.0',
        '->first returns the correct IP address'
    );

    my $last = $net->last();
    isa_ok(
        $last,
        'MM::Net::IPAddress',
        'return value of ->last'
    );

    is(
        $last->as_string(),
        '1.1.1.15',
        '->last returns the correct IP address'
    );

    _test_iterator(
        $net,
        16,
        [ map { "1.1.1.$_" } 0 .. 15 ],
    );
}

{
    my $net = MM::Net::Subnet->new( subnet => 'ffff::1200/120' );

    is(
        $net->as_string(),
        'ffff::1200/120',
        'as_string returns value passed to the constructor'
    );

    is(
        $net->netmask_as_integer(),
        120,
        'netmask is 120',
    );

    my $first = $net->first();
    isa_ok(
        $first,
        'MM::Net::IPAddress',
        'return value of ->first'
    );

    is(
        $first->as_string(),
        'ffff::1200',
        '->first returns the correct IP address'
    );

    my $last = $net->last();
    isa_ok(
        $last,
        'MM::Net::IPAddress',
        'return value of ->last'
    );

    is(
        $last->as_string(),
        'ffff::12ff',
        '->last returns the correct IP address'
    );

    _test_iterator(
        $net,
        256,
        [ map { sprintf( "ffff::12%02x", $_ ) } 0 .. 255 ],
    );
}

{
    my $net = MM::Net::Subnet->new( subnet => '1.1.1.1/32' );

    _test_iterator(
        $net,
        1,
        ['1.1.1.1'],
    );
}

{
    my $net = MM::Net::Subnet->new( subnet => '1.1.1.0/31' );

    _test_iterator(
        $net,
        2,
        [ '1.1.1.0', '1.1.1.1' ],
    );
}

{
    my $net = MM::Net::Subnet->new( subnet => '1.1.1.4/30' );

    _test_iterator(
        $net,
        4,
        [ '1.1.1.4', '1.1.1.5', '1.1.1.6', '1.1.1.7' ],
    );
}

{
    my %tests = (
        ( map { '100.99.98.0/' . $_ => 23 } 23 .. 32 ),
        ( map { '100.99.16.0/' . $_ => 20 } 20 .. 32 ),
        ( map { '1.1.1.0/' . $_     => 24 } 24 .. 32 ),
        ( map { 'ffff::/' . $_      => 16 } 16 .. 128 ),
        ( map { 'ffff:ff00::/' . $_ => 24 } 24 .. 128 ),
    );

    for my $subnet ( sort keys %tests ) {
        my $net = MM::Net::Subnet->new( subnet => $subnet );

        is(
            $net->max_netmask(),
            $tests{$subnet},
            "max_netmask for $subnet is $tests{$subnet}"
        );
    }
}

sub _test_iterator {
    my $net              = shift;
    my $expect_count     = shift;
    my $expect_addresses = shift;

    my $iter = $net->iterator();

    my @addresses;
    while ( my $address = $iter->() ) {
        push @addresses, $address;
    }

    is(
        scalar @addresses,
        $expect_count,
        "iterator returned $expect_count addresses"
    );

    is_deeply(
        [ map { $_->as_string() } @addresses ],
        $expect_addresses,
        "iterator returned $expect_addresses->[0] - $expect_addresses->[-1]"
    );
}

done_testing();
