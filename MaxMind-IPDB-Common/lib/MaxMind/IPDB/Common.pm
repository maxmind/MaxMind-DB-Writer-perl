package MaxMind::IPDB::Common;

use strict;
use warnings;

use constant {
    LEFT_RECORD  => 0,
    RIGHT_RECORD => 1,
};

use Exporter qw( import );

our @EXPORT_OK = qw( LEFT_RECORD RIGHT_RECORD );

1;

# ABSTRACT: Code shared by the IPDB reader and writer modules

