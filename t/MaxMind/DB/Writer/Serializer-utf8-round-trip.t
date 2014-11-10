use strict;
use warnings;

use lib 't/lib';

use Test::More;

use Encode ();
use MaxMind::DB::Reader::Decoder;
use MaxMind::DB::Writer::Serializer;

{
    my $tb = Test::Builder->new();

    binmode $_, ':encoding(UTF-8)'
        for $tb->output(),
        $tb->failure_output(),
        $tb->todo_output();
}

my $input = "\x{4eba}";

ok(
    Encode::is_utf8($input),
    'input is marked as utf8 in Perl'
);

my $serializer
    = MaxMind::DB::Writer::Serializer->new( map_key_type_callback => sub { }
    );
$serializer->store_data( utf8_string => $input );

my $buffer = $serializer->buffer();
open my $fh, '<:raw', $buffer;

my $decoder = MaxMind::DB::Reader::Decoder->new(
    data_source       => $fh,
    _data_source_size => bytes::length( ${$buffer} ),
);

my $output = $decoder->decode(0);

ok(
    Encode::is_utf8($output),
    'output is marked as utf8 in Perl'
);

is(
    $input,
    $output,
    "utf-8 string ($input) makes round trip from serializer to decoder safely"
);

done_testing();
