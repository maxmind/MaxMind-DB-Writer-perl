package MaxMind::IPDB::Role::Debugs;

use strict;
use warnings;
use namespace::autoclean;
use autodie;

use Moose::Role;

sub _debug_newline {
    warn "\n";
}

sub _debug_binary {
    my $self   = shift;
    my $label  = shift;
    my $binary = shift;

    my $msg = "$label: ";

    if ( defined $binary ) {
        $msg .= join q{ }, map { sprintf( "%08b", ord($_) ) } split //,
            $binary;
    }
    else {
        $msg .= '<undef>';
    }

    warn "$msg\n";
}

sub _debug_string {
    my $self   = shift;
    my $label  = shift;
    my $string = shift;

    $string //= '<undef>';

    warn "$label: $string\n";
}

sub _debug_structure {
    my $self = shift;
    my $label = shift;
    my $structure = shift;

    require Data::Dumper::Concise;
    warn "$label: \n";
    my $dumped = Data::Dumper::Concise::Dumper($structure);

    $dumped =~ s/^/  /mg;

    warn $dumped;
}

sub _debug_message {
    my $self = shift;
    my $msg  = shift;

    warn "$msg\n";
}

1;
