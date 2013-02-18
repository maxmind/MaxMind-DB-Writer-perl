package MaxMind::IPDB::Reader::Role::Sysreader;

use strict;
use warnings;
use namespace::autoclean;
use autodie;

use Moose::Role;

has data_source => (
    is      => 'ro',
    isa     => 'FileHandle',
    lazy    => 1,
    builder => '_build_data_source',
);

sub _read {
    my $self          = shift;
    my $buffer        = shift;
    my $offset        = shift;
    my $wanted_size   = shift;
    my $seek_from_end = shift;

    my $source = $self->data_source();
    seek $source, $offset, $seek_from_end ? 2 : 0;

    my $read_offset = 0;
    while (1) {
        my $read_size = read(
            $source,
            ${$buffer},
            $wanted_size,
            $read_offset,
        );

        confess $! unless defined $read_size;

        # This error message doesn't provide much context, but it should only
        # be thrown because of a fundamental logic error in the reader code,
        # _or_ because the writer generated a database with broken pointers
        # and/or broken data elements.
        confess 'Attempted to read past the end of a file/memory buffer'
            if $read_size == 0;

        return if $wanted_size == $read_size;

        $wanted_size -= $read_size;
        $read_offset += $read_size;
    }

    return;
}

sub _build_data_source {
    my $class = ref shift;

    die "You must provide a data_source parameter to the constructor for $class";
}

1;
