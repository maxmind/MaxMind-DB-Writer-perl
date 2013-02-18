package MaxMind::DB::Reader::Data::EndMarker;

use strict;
use warnings;

sub new {
    my $str = 'end marker';
    return bless \$str, __PACKAGE__;
}

1;
