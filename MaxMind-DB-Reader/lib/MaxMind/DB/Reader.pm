package MaxMind::DB::Reader;

use strict;
use warnings;
use namespace::autoclean;

use Data::Validate::Domain qw( is_hostname );
use Data::Validate::IP qw( is_ipv4 is_ipv6 is_private_ipv4 );
use MaxMind::DB::Metadata;
use MaxMind::DB::Reader::File;
use Socket qw( inet_ntoa );

#use MaxMind::DB::Reader::Memory;
#use MaxMind::DB::Reader::PartialMemory;

use Moose;

has file => (
    is       => 'ro',
    required => 0,
);

has _reader => (
    is       => 'ro',
    does     => 'MaxMind::DB::Reader::Role::Reader',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_reader',
    handles  => [ 'metadata', MaxMind::DB::Metadata->meta()->get_attribute_list() ],
);

sub BUILD {
    my $self = shift;

    my $file = $self->file();

    die "The file you specified ($file) does not exist"
        if $file && !-e $file;

    die "The file you specified ($file) cannot be read"
        if $file && !-r _;

    return;
}

sub record_for_address {
    my $self = shift;
    my $addr = shift;

    die 'You must provide an IP address to look up'
        unless defined $addr and length $addr;

    die
        "The IP address you provided ($addr) is not a valid IPv4 or IPv6 adress"
        unless is_ipv4($addr) || is_ipv6($addr);

    die "The IP address you provided ($addr) is not a public IP address"
        if is_private_ipv4($addr) || _is_private_ipv6($addr);

    return $self->_reader()->data_for_address($addr);
}

sub record_for_hostname {
    my $self     = shift;
    my $hostname = shift;

    die 'You must provide a hostname to look up'
        unless defined $hostname and length $hostname;

    die "The name you provided ($hostname) is not a valid hostname"
        unless is_hostname($hostname);

    return $self->record_for_address( $self->_resolve_hostname($hostname) );
}

sub _resolve_hostname {
    my $self     = shift;
    my $hostname = shift;

    my $packed_ip = gethostbyname($hostname);
    if ( defined $packed_ip ) {
        return inet_ntoa($packed_ip);
    }

    return;
}

# XXX - this needs an implementation - couldn't find anything on CPAN which
# seemed to handle IPv6 netmasks or know which IPv6 networks are private.
sub _is_private_ipv6 {
    return 0;
}

sub _build_reader {
    my $self = shift;
    return MaxMind::DB::Reader::File->new( file => $self->file );
}

__PACKAGE__->meta()->make_immutable();

1;

# ABSTRACT: Read MaxMind DB files
