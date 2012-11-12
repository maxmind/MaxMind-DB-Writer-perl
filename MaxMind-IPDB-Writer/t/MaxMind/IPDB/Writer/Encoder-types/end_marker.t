use strict;
use warnings;

use lib 't/lib';

use Test::Bits;
use Test::More;

use MaxMind::IPDB::Writer::Encoder;

{
    my $output;
    open my $fh, '>', \$output;

    my $encoder = MaxMind::IPDB::Writer::Encoder->new( output => $fh );
    $encoder->encode_end_marker();

    bits_is(
        $output,
        [ 0b00000000, 0b00001101 ],
        'encoding of end_marker type'
    );
}

done_testing();
