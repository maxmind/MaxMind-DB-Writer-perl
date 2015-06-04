package MaxMind::DB::Writer::Util;

use strict;
use warnings;

our $VERSION = '0.100004';

use Digest::SHA1 qw( sha1_base64 );
use Encode qw( encode );
use Sereal::Encoder;

use Exporter qw( import );
our @EXPORT_OK = qw( key_for_data );

{
    my $Encoder = Sereal::Encoder->new( { sort_keys => 1 } );

    sub key_for_data {

        # We need to use sha1 because the Sereal structure has \0 bytes which
        # confuse the C code. As a bonus, this makes the keys smaller so they
        # take up less space. As an un-bonus, this makes the code a little
        # slower.
        my $key = ref $_[0] ? $Encoder->encode( $_[0] ) : $_[0];
        return sha1_base64( encode( 'UTF-8', $key ) );
    }
}

1;
