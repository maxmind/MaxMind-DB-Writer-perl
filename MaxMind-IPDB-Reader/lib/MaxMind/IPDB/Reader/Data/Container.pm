package MaxMind::IPDB::Reader::Data::Container;

use strict;
use warnings;

sub new {
    my $str = 'container';
    return bless \$str, __PACKAGE__;
}

1;
