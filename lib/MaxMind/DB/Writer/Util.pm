package MaxMind::DB::Writer::Util;

use strict;
use warnings;

our $VERSION = '0.201005';

use Digest::SHA1 qw( sha1_base64 );
use Encode qw( encode );
use Sereal::Encoder 3.002 qw( sereal_encode_with_object );

use Exporter qw( import );
our @EXPORT_OK = qw( key_for_data );

{
    # Although this mostly works fine when canonical and canonical_refs are
    # enabled, it is still somewhat broken. See:
    #
    # https://metacpan.org/pod/distribution/Sereal-Encoder/lib/Sereal/Encoder.pm#CANONICAL-REPRESENTATION
    #
    # The arrays in the example, for instance, would have distinct keys
    # despite being structurally equivalent. Requires Sereal 3.002.
    my $Encoder = Sereal::Encoder->new(
        {
            canonical      => 1,
            canonical_refs => 1,
        }
    );

    sub key_for_data {

        # We need to use sha1 because the Sereal structure has \0 bytes which
        # confuse the C code. As a bonus, this makes the keys smaller so they
        # take up less space. As an un-bonus, this makes the code a little
        # slower.
        my $key
            = ref $_[0]
            ? sereal_encode_with_object( $Encoder, $_[0] )
            : encode( 'UTF-8', $_[0] );

        return sha1_base64($key);
    }
}

1;
