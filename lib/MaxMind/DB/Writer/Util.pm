package MaxMind::DB::Writer::Util;

use strict;
use warnings;

use Sereal::Encoder;

use Exporter qw( import );
our @EXPORT_OK = qw( key_for_data );

{
    my $Encoder = Sereal::Encoder->new( { sort_keys => 1 } );

    sub key_for_data {
        return ref $_[0] ? $Encoder->encode( $_[0] ) : $_[0];
    }
}

1;
