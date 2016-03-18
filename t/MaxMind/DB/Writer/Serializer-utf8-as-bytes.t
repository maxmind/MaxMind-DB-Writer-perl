use strict;
use warnings;
use utf8;

use lib 't/lib';

use Test::Fatal;
use Test::More;

use Encode ();
use MaxMind::DB::Reader::Decoder;
use MaxMind::DB::Writer::Serializer;

{
    my $tb = Test::Builder->new();

    binmode $_, ':encoding(UTF-8)' for $tb->output(),
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

like(
    exception { $serializer->store_data( bytes => $input ) },
    qr/\QYou attempted to store a characters string (人) as bytes/,
    'got an error when trying to serialize a character string as bytes'
);

done_testing();
