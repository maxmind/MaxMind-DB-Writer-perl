package MaxMind::DB::Writer;

use strict;
use warnings;
use 5.013002;

our $VERSION = '0.201005';

1;

# ABSTRACT: Create MaxMind DB database files

__END__

=pod

=head1 SYNOPSIS

    use MaxMind::DB::Writer::Tree;

    my %types = (
        color => 'utf8_string',
        dogs  => [ 'array', 'utf8_string' ],
        size  => 'uint16',
    );

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version            => 6,
        record_size           => 24,
        database_type         => 'My-IP-Data',
        languages             => ['en'],
        description           => { en => 'My database of IP data' },
        map_key_type_callback => sub { $types{ $_[0] } },
    );

    $tree->insert_network(
        '2001:db8::/48',
        {
            color => 'blue',
            dogs  => [ 'Fido', 'Ms. Pretty Paws' ],
            size  => 42,
        },
    );

    open my $fh, '>:raw', '/path/to/my-ip-data.mmdb';
    $tree->write_tree($fh);

=head1 DESCRIPTION

This distribution contains the code necessary to write L<MaxMind DB database
files|http://maxmind.github.io/MaxMind-DB/>. See L<MaxMind::DB::Writer::Tree>
for API docs.

=head1 MAC OS X SUPPORT

If you're running into install errors under Mac OS X, you may need to force a
build of the 64 bit binary. For example, if you're installing via C<cpanm>:

    ARCHFLAGS="-arch x86_64" cpanm MaxMind::DB::Writer

=head1 WINDOWS SUPPORT

This distribution does not currently work on Windows. Reasonable patches for
Windows support are very welcome. You will probably need to start by making
L<Math::Int128> work on Windows, since we use that module's C API for dealing
with 128-bit integers to represent IPv6 addresses numerically.

=head1 SUPPORT

Please report all issues with this code using the GitHub issue tracker at
L<https://github.com/maxmind/MaxMind-DB-Writer-perl/issues>.

We welcome patches as pull requests against our GitHub repository at
L<https://github.com/maxmind/MaxMind-DB-Writer-perl>.

=cut
