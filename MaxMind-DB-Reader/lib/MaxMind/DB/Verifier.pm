package MaxMind::DB::Verifier;

use strict;
use warnings;
use namespace::autoclean;
use autodie;

use IO::File;
use MaxMind::DB::Common qw( DATA_SECTION_SEPARATOR_SIZE );
use MaxMind::DB::Metadata;
use Try::Tiny;

use Moose;
use MooseX::StrictConstructor;

with 'MooseX::Getopt::Dashes',
    'MaxMind::DB::Reader::Role::NodeReader',
    'MaxMind::DB::Reader::Role::HasDecoder';

has file => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has quiet => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has _max_pointer_in_search_tree => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_max_pointer_in_search_tree',
);

has _search_tree_data_pointers => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub { {} },
);

has _error_count => (
    traits   => ['Counter'],
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
    handles  => {
        _inc_error_count => 'inc',
    },
);

sub run {
    my $self = shift;

    $self->verify();
}

sub verify {
    my $self = shift;

    STDOUT->autoflush(1);

    for my $thing (qw( metadata search_tree data_section )) {
        my $display_name = $thing =~ s/_/ /gr;

        $self->_output("Verifying $display_name ...");

        my $method = '_verify_' . $thing;
        $self->$method();

        if ( $self->_error_count() ) {
            warn "Cannot continue verification with bad $display_name\n";
            return 0;
        }
        else {
            $self->_output('   ok');
        }
    }

    return 1;
}

sub _verify_metadata {
    my $self = shift;

    my $node_count = $self->node_count();
    unless ( $node_count > 0 ) {
        $self->_verification_error(
            "The metadata specified the node count was $node_count - we expect a positive number"
        );
    }

    my $record_size = $self->record_size();
    unless ( $record_size >= 24
        && $record_size <= 64
        && $record_size % 4 == 0 ) {
        $self->_verification_error(
            "The metadata specified a record size of $record_size - we expect a number from 24 to 64 that is divisible by 4"
        );
    }
}

sub _verify_search_tree {
    my $self = shift;

    $self->_output('  looking for data section separator');
    $self->_verify_data_section_separator();

    $self->_output('  checking all nodes');
    $self->_verify_all_nodes();

    return;
}

my $DataSectionSeparator = "\0" x 16;

sub _verify_data_section_separator {
    my $self = shift;

    my $marker;
    $self->_read( \$marker, $self->_search_tree_size(), 16 );

    unless ( $marker eq $DataSectionSeparator ) {
        $self->_verification_error(
            'Did not find the data section start marker at the expected place'
        );
    }
}

sub _verify_all_nodes {
    my $self = shift;

    my $expected_count = $self->node_count();
    my $node_num       = 0;

    while ( $node_num < $expected_count ) {
        $self->_verify_node($node_num);
        $node_num++;

        if ( $node_num % 10000 == 0 ) {
            $self->_output("  checked $node_num nodes out of $expected_count");
        }
    }
}

{
    my @directions = ( 'left', 'right' );

    sub _verify_node {
        my $self     = shift;
        my $node_num = shift;

        my $node_count = $self->node_count();

        my %records;
        @records{@directions} = $self->_read_node($node_num);

        for my $dir (@directions) {
            if ( $records{$dir} == 0 ) {
                $self->_verification_error(
                    "Node $node_num, $dir record == 0");
            }

            next if $records{$dir} <= $self->node_count();

            my $resolved
                = ( $records{$dir} - $self->node_count() )
                    + $self->_search_tree_size();

            if ( $resolved <= $self->_max_pointer_in_search_tree() ) {
                $self->_search_tree_data_pointers()->{$resolved}
                    = [ $node_num, $dir ];
            }
            else {
                $self->_verification_error(
                    "Node $node_num, $dir record points past the end of the data section"
                );
            }
        }

        return;
    }
}

sub _verify_data_section {
    my $self = shift;

    my $pointers = $self->_search_tree_data_pointers();
    my $pointer_count = scalar keys %{$pointers};

    my $decoder  = $self->_decoder();

    my $data_section_start
        = $self->_search_tree_size() + DATA_SECTION_SEPARATOR_SIZE;
    my $offset = $data_section_start;

    my $data_section_end = $self->_data_section_end();

    while ( $offset < $data_section_end ) {
        my ( $data, $new_offset );
        try {
            ( $data, $new_offset ) = $self->_decoder()->decode($offset);
        }
        catch {
            $self->_verification_error(
                "Error stepping through the data section at offset $offset - $_"
            );
        };

        last unless $data;

        if ( $new_offset <= $offset ) {
            $self->_verification_error(
                "Something weird happened in the decoder - the offset went from $offset to $new_offset"
            );
        }

        if ( $pointers->{$offset} ) {
            delete $pointers->{$offset};
        }
        else {
            $self->_verification_error(
                "Found a chunk of data in the section (file offset $offset) that the search tree does not point to"
            );
        }

        $offset = $new_offset;
    }

    if ( my $final_count = keys %{$pointers} ) {
        $self->_verification_error(
            "Found $final_count pointers (of $pointer_count) in the search tree"
                . " that we didn't see while stepping through the data section"
        );
    }
}

sub _verification_error {
    my $self  = shift;
    my $error = shift;

    $self->_inc_error_count();

    warn "$error\n";
}

sub _output {
    my $self = shift;

    return if $self->quiet();

    print "$_[0]\n";
}

sub _build_data_source {
    my $self = shift;

    open my $fh, '<:raw', $self->file();

    return $fh;
}

sub _build_max_pointer_in_search_tree {
    my $self = shift;

    # We should not find something that resolves past the last byte of the
    # data section.
    return $self->_data_section_end() - 1;
}

__PACKAGE__->meta()->make_immutable();

1;
