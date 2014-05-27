package MaxMind::DB::Writer;

use strict;
use warnings;

1;

# ABSTRACT: Create MaxMind DB database files

__END__

=pod

=head1 SYNOPSIS

    use MaxMind::DB::Writer::Tree;
    use Net::Works::Network;

    my $tree = MaxMind::DB::Writer::Tree->new(
        ip_version    => 6,
        record_size   => 24,
        database_type => 'My-IP-Data',
        languages     => ['en'],
        description   => { en => 'My database of IP data' },
    );

    my $network
        = Net::Works::Network->new_from_string( string => '8.23.0.0/16' );

    $tree->insert_network(
        $network,
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

=cut
