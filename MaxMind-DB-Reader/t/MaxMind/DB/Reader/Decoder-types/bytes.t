use strict;
use warnings;

use lib 't/lib';

use Test::MaxMind::DB::Common::Data qw( test_cases_for );
use Test::MaxMind::DB::Reader::Decoder qw( test_decoding_of_type );
use Test::More;

use Encode ();

{
    my $tb = Test::Builder->new();

    binmode $_, ':encoding(UTF-8)'
        for $tb->output(),
        $tb->failure_output(),
        $tb->todo_output();
}

test_decoding_of_type( bytes => test_cases_for('bytes') );

{
    my $buffer = pack(
        'C4' => 0b10000011,
        0b11100100, 0b10111010, 0b10111010
    );

    open my $fh, '<', \$buffer;

    my $decoder = MaxMind::DB::Reader::Decoder->new(
        data_source => $fh,
    );

    my $string = $decoder->decode(0);

    ok(
        !Encode::is_utf8($string),
        'utf8 flag is off for bytes returned by decoder'
    );
}


done_testing();
