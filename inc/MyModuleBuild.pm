## no critic (NamingConventions::Capitalization)
package inc::MyModuleBuild;

use strict;
use warnings;
use namespace::autoclean;

use Moose;

extends 'Dist::Zilla::Plugin::ModuleBuild';

my $template = <<'EOT';
use strict;
use warnings;

use lib 'inc';

use Config qw( %Config );
use Config::AutoConf;
use Module::Build;

if ( $^O =~ /Win32/ ) {
    die 'This distribution does not work on Windows platforms.'
        . " See the documentation for details.\n";
}

my {{ $module_build_args }}
my $mb = Module::Build->new(
    %module_build_args,
    c_source => 'c',
);

$mb->extra_compiler_flags( _cc_flags($mb) );

$mb->create_build_script();

sub _cc_flags {
    my $mb = shift;

    my %unique = map { $_ => 1 } qw( -std=c99 -fms-extensions -Wall -g ),
        @{ $mb->extra_compiler_flags || [] },
        _int64_define(),
        _int128_define();

    return keys %unique;
}

sub _int64_define {
    my $autoconf = Config::AutoConf->new;

    return unless $autoconf->check_default_headers();
    return '-DINT64_T' if $autoconf->check_type('int64_t');
    return '-D__INT64' if $autoconf->check_type('__int64');
    return '-DINT64_DI'
        if $autoconf->check_type('int __attribute__ ((__mode__ (DI)))');

    warn <<'EOF';

  It looks like your compiler doesn't support a 64-bit integer type (one of
  "int64_t" or "__int64"). One of these types is necessary to compile the
  Math::Int64 module.

EOF

    exit 1;
}

sub _int128_define {
    my $autoconf = Config::AutoConf->new;

    return unless $autoconf->check_default_headers();
    return '-D__INT128' if _check_type( $autoconf, '__int128' );
    return '-DINT128_TI'
        if _check_type( $autoconf, 'int __attribute__ ((__mode__ (TI)))' );

    warn <<'EOF';

  It looks like your compiler doesn't support a 128-bit integer type (one of
  "int __attribute__ ((__mode__ (TI)))" or "__int128"). One of these types is
  necessary to compile the Math::Int128 module.

EOF

    exit 1;
}

# This more complex check is needed in order to ferret out bugs with clang on
# i386 platforms. See http://llvm.org/bugs/show_bug.cgi?id=15834 for the bug
# report. This appears to be
sub _check_type {
    my $autoconf = shift;
    my $type     = shift;

    my $uint64_type
        = $autoconf->check_type('uint64_t') ? 'uint64_t'
        : $autoconf->check_type(
        'unsigned int __attribute__ ((__mode__ (DI)))')
        ? 'unsigned int __attribute__ ((__mode__ (DI)))'
        : return 0;

    my $cache_name = $autoconf->_cache_type_name( 'type', $type );
    my $check_sub = sub {
        my $prologue = $autoconf->_default_includes();
        $prologue .=
            $type =~ /__mode__/
            ? "typedef unsigned uint128_t __attribute__((__mode__(TI)));\n"
            : "typedef unsigned __int128 uint128_t;\n";

        # The rand() calls are there because if we just use constants than the
        # compiler can optimize most of this code away.
        my $body = <<"EOF";
$uint64_type a = (($uint64_type)rand()) * rand();
$uint64_type b = (($uint64_type)rand()) << 24;
uint128_t c = ((uint128_t)a) * b;
return c > rand();
EOF
        my $conftest = $autoconf->lang_build_program( $prologue, $body );
        return $autoconf->compile_if_else($conftest);
    };

    return $autoconf->check_cached( $cache_name, "for $type", $check_sub );
}
EOT

sub gather_files {
    my ($self) = @_;

    require Dist::Zilla::File::InMemory;

    my $file = Dist::Zilla::File::InMemory->new(
        {
            name    => 'Build.PL',
            content => $template,    # template evaluated later
        }
    );

    $self->add_file($file);
    return;
}

__PACKAGE__->meta()->make_immutable();

1;
