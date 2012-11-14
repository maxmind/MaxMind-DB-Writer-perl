use strict;
use warnings;

use Test::More;

use MaxMind::IPDB::Metadata;
use MaxMind::IPDB::Writer::Tree::InMemory;
use MaxMind::IPDB::Writer::Tree::File;

use MM::Net::Subnet;

for my $record_size ( 24, 28, 32 ) {
    {
        my $desc = "IPv4 - $record_size-bit record";

        my $buffer = _write_tree(
            $record_size,
            [ MM::Net::Subnet->range_as_subnets( '1.1.1.1', '1.1.1.32' ) ],
            { ip_version => 4 },
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

    {
        my $desc = "IPv6 - $record_size-bit record";

        my $buffer = _write_tree(
            $record_size,
            [
                MM::Net::Subnet->range_as_subnets(
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
}

done_testing();

sub _write_tree {
    my $record_size = shift;
    my $subnets  = shift;
    my $metadata = shift;

    my $tree = MaxMind::IPDB::Writer::Tree::InMemory->new();

    for my $subnet ( @{$subnets} ) {
        $tree->insert_subnet(
            $subnet,
            { ip => $subnet->first()->as_string() }
        );
    }

    my $writer = MaxMind::IPDB::Writer::Tree::File->new(
        tree          => $tree,
        record_size   => $record_size,
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
        %{$metadata},
    );

    my $buffer;
    open my $fh, '>', \$buffer;

    $writer->write_tree($fh);

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
        MaxMind::IPDB::Metadata->meta()->get_all_attributes() ) {

        like(
            $buffer,
            qr/\xab\xcd\xefMaxMind\.com.*\Q$key/s,
            "written-out database includes metadata key $key - $desc"
        );
    }

}
