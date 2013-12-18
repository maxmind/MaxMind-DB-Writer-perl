use strict;
use warnings;

use Test::More;

use MaxMind::DB::Common qw( DATA_SECTION_SEPARATOR );
use MaxMind::DB::Metadata;
use MaxMind::DB::Writer::Tree;

use Net::Works::Network;

_test_search_tree_output();

for my $record_size ( 24, 28, 32 ) {
    _test_ipv4_networks($record_size);
    _test_ipv6_networks($record_size);
}

done_testing();

sub _test_search_tree_output {
    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 4,
        record_size   => 24,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        map_key_type_callback => sub { 'utf8_string' },
    );

    my @subnets = map { Net::Works::Network->new_from_string( string => $_ ) }
        qw( 0.0.0.0/2 128.0.0.0/2 );

    for my $subnet (@subnets) {
        $tree->insert_network(
            $subnet,
            { ip => $subnet->first()->as_string() }
        );
    }

    my $node_count = 3;

    is(
        $tree->node_count(),
        $node_count,
        "tree has $node_count nodes"
    );

    my $buffer;
    open my $fh, '>:raw', \$buffer;

    $tree->write_tree($fh);

    my $separator = DATA_SECTION_SEPARATOR;

    my $search_tree_size = $node_count * 6;
    like(
        $buffer,
        qr/^.{$search_tree_size}\Q$separator/,
        "tree output starts with a search tree of $search_tree_size bytes"
    );

    my $one = substr( pack('N', 1 ), 1, 3);
    my $two = substr( pack('N', 2 ), 1, 3);

    like(
        $buffer,
        qr/\Q$one$two/,
        'first node in search tree points to nodes 1 (L) and 2 (R)'
    );

    # The 3 node search tree is 18 bytes long.
    my $data_section_size = length($buffer) - $search_tree_size;

    my ( $node_1_left_record, $node_2_left_record )
        = map { unpack( 'N', pack( 'xa3', unpack( 'a3', $_ ) ) ) }
        $buffer =~ /^.{6}(.{3}).{3}(.{3})/;

    cmp_ok(
        $node_1_left_record, '>', 2,
        'node 1 left record points to a value outside the search tree'
    );

    cmp_ok(
        $node_1_left_record - $node_count, '<', $data_section_size,
        'node 1 left record points to a value in the data section'
    );

    cmp_ok(
        $node_2_left_record, '>', 2,
        'node 2 left record points to a value outside the search tree'
    );

    cmp_ok(
        $node_2_left_record - $node_count, '<', $data_section_size,
        'node 2 left record points to a value in the data section'
    );

}

sub _test_ipv4_networks {
    my $record_size = shift;

    my $desc = "IPv4 - $record_size-bit record";

    my $buffer = _write_tree(
        $record_size,
        [
            Net::Works::Network->range_as_subnets(
                '1.1.1.1', '1.1.1.32'
            )
        ],
        { ip_version => 4 },
    );

    like(
        $buffer,
        qr/\0{16}/,
        "written-out database includes 16 bytes of 0s"
    );

    my $expect = join q{}, map { chr($_) } (

        # map with 1 key
        0b11100001,
        (
            # ip
            0b01000010,
            0b01101001, 0b01110000,
        ),
        (    # 1.1.1.1
            0b01000111,
            0b00110001, 0b00101110, 0b00110001,
            0b00101110, 0b00110001, 0b00101110, 0b00110001
        ),
    );

    like(
        $buffer,
        qr/\Q$expect/,
        "written-out database includes expected data for one subnet - $desc"
    );

    _test_metadata( $buffer, $desc );
}

sub _test_ipv6_networks {
    my $record_size = shift;

    my $desc = "IPv6 - $record_size-bit record";

    my $buffer = _write_tree(
        $record_size,
        [
            Net::Works::Network->range_as_subnets(
                '::1:ffff:ffff', '::2:0000:0059'
            )
        ],
        { ip_version => 6 },
    );

    my $expect = join q{}, map { chr($_) } (

        # map with 1 key
        0b11100001,
        (
            # ip
            0b01000010,
            0b01101001, 0b01110000,
        ),
        (
            # ::1:ffff:ffff
            0b01001101,
            0b00111010, 0b00111010, 0b00110001, 0b00111010,
            0b01100110, 0b01100110, 0b01100110, 0b01100110,
            0b00111010, 0b01100110, 0b01100110, 0b01100110, 0b01100110
        ),
    );

    like(
        $buffer,
        qr/\Q$expect/,
        "written-out database includes expected data for one subnet - $desc"
    );

    _test_metadata( $buffer, $desc );
}

sub _write_tree {
    my $record_size = shift;
    my $subnets     = shift;
    my $metadata    = shift;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => $metadata->{ip_version},
        record_size   => $record_size,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        map_key_type_callback => sub { 'utf8_string' },
    );

    for my $subnet ( @{$subnets} ) {
        $tree->insert_network(
            $subnet,
            { ip => $subnet->first()->as_string() }
        );
    }

    my $buffer;
    open my $fh, '>', \$buffer;

    $tree->write_tree($fh);

    return $buffer;
}

sub _test_metadata {
    my $buffer = shift;
    my $desc   = shift;

    like(
        $buffer,
        qr/\xab\xcd\xefMaxMind\.com/,
        "written-out database includes metadata start marker - $desc"
    );

    for my $key ( sort map { $_->name() }
        MaxMind::DB::Metadata->meta()->get_all_attributes() ) {

        like(
            $buffer,
            qr/\xab\xcd\xefMaxMind\.com.*\Q$key/s,
            "written-out database includes metadata key $key - $desc"
        );
    }

}
