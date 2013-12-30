package MaxMind::DB::Writer::Role::KeyMaker;

use strict;
use warnings;
use namespace::autoclean;

use Sereal::Encoder;

use Moose::Role;

{
    my $Encoder = Sereal::Encoder->new( { sort_keys => 1 } );

    sub _key_for_data {
        return ref $_[1] ? $Encoder->encode( $_[1] ) : $_[1];
    }
}

1;
