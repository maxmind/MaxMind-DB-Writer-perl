use strict;
use warnings;

use Test::Bits;
use Test::More;

use MaxMind::DB::Writer::Tree::InMemory;
use MaxMind::DB::Writer::Tree::File;

my $tree = MaxMind::DB::Writer::Tree::InMemory->new( ip_version => 4 );
$tree->{_used_node_count} = 850_000;

my $writer = MaxMind::DB::Writer::Tree::File->new(
    tree          => $tree,
    record_size   => 28,
    ip_version    => 4,
    database_type => 'Test',
    languages     => [ 'en', 'zh' ],
    description   => {
        en => 'Test Database',
        zh => 'Test Database Chinese',
    },
    map_key_type_callback => sub { 'utf8_string' },
);

{
    my $node_num = 500_000;
    $writer->_encode_record(
        $node_num,
        0,
        234_567_890,
    );
    $writer->_encode_record(
        $node_num,
        1,
        234_567_891,
    );

    my $offset = $node_num * 7;

    bits_is(
        substr( ${ $writer->_tree_buffer() }, $offset, 7 ),
        [
            0b11111011, 0b00111000, 0b11010010,
            0b11011101,
            0b11111011, 0b00111000, 0b11010011
        ],
        'node with 28-bit record encodes 28-bit number correctly - encoded left then right',
    );
}

{
    my $node_num = 500_000;
    $writer->_encode_record(
        $node_num,
        1,
        234_567_891,
    );
    $writer->_encode_record(
        $node_num,
        0,
        234_567_890,
    );

    my $offset = $node_num * 7;

    bits_is(
        substr( ${ $writer->_tree_buffer() }, $offset, 7 ),
        [
            0b11111011, 0b00111000, 0b11010010,
            0b11011101,
            0b11111011, 0b00111000, 0b11010011
        ],
        'node with 28-bit record encodes 28-bit number correctly - encoded right then left',
    );
}

done_testing();
