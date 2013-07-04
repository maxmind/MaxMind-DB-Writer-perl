package MaxMind::DB::Common;

use strict;
use warnings;

use constant {
    LEFT_RECORD                 => 0,
    RIGHT_RECORD                => 1,
    DATA_SECTION_SEPARATOR_SIZE => 16,
};

use Exporter qw( import );

our @EXPORT_OK = qw( LEFT_RECORD RIGHT_RECORD DATA_SECTION_SEPARATOR_SIZE );

1;

# ABSTRACT: Code shared by the MaxMind::DB:Reader and MaxMind::DB::Writer modules

