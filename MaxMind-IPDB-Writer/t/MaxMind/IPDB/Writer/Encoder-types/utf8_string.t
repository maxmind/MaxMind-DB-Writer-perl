use strict;
use warnings;

use lib 't/lib';

use Test::Fatal;
use Test::MaxMind::IPDB::Common::Data qw( test_cases_for );
use Test::MaxMind::IPDB::Writer::Encoder qw( test_encoding_of_type );
use Test::More;

{
    my $tb = Test::Builder->new();

    binmode $_, ':encoding(UTF-8)'
        for $tb->output(),
        $tb->failure_output(),
        $tb->todo_output();
}

test_encoding_of_type( utf8_string => test_cases_for('utf8_string') );

{
    my $max_size = ( 2**24 - 1 ) + 65821;
    my $string_too_big = 'x' x ( $max_size + 1 );

    my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => \*STDOUT );

    like(
        exception { $encoder->encode_utf8_string($string_too_big) },
        qr/\QCannot store 16843037 bytes - max size is 16843036 bytes/,
        "encoder dies when asked to encode more than $max_size bytes of data"
    );
}

done_testing();
