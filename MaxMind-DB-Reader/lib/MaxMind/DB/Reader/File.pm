package MaxMind::DB::Reader::File;

use strict;
use warnings;
use autodie;
use namespace::autoclean;

use Moose;
use MooseX::StrictConstructor;

with 'MaxMind::DB::Reader::Role::Reader';

has file => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

sub _build_data_source {
    my $self = shift;

    open my $fh, '<:raw', $self->file();

    return $fh;
}

__PACKAGE__->meta()->make_immutable();

1;
