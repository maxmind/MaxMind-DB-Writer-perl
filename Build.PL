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

my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.28"
  },
  "configure_requires" => {
    "Module::Build" => "0.28"
  },
  "dist_abstract" => "Create MaxMind DB database files",
  "dist_author" => [
    "Olaf Alders <oalders\@maxmind.com>",
    "Greg Oschwald <goschwald\@maxmind.com>",
    "Dave Rolsky <drolsky\@maxmind.com>",
    "Mark Fowler <mfowler\@maxmind.com>"
  ],
  "dist_name" => "MaxMind-DB-Writer",
  "dist_version" => "0.201004",
  "license" => "perl",
  "module_name" => "MaxMind::DB::Writer",
  "recursive_test_files" => 1,
  "requires" => {
    "Carp" => 0,
    "Data::Dumper::Concise" => 0,
    "Data::IEEE754" => 0,
    "Digest::MD5" => 0,
    "Digest::SHA1" => 0,
    "Encode" => 0,
    "Exporter" => 0,
    "IO::Handle" => 0,
    "Math::Int128" => "0.21",
    "Math::Int64" => "0.51",
    "MaxMind::DB::Common" => "0.031003",
    "MaxMind::DB::Metadata" => 0,
    "MaxMind::DB::Reader::Decoder" => 0,
    "MaxMind::DB::Role::Debugs" => 0,
    "Moose" => 0,
    "Moose::Util::TypeConstraints" => 0,
    "MooseX::Params::Validate" => 0,
    "MooseX::StrictConstructor" => 0,
    "Net::Works::Network" => 0,
    "Sereal::Decoder" => 0,
    "Sereal::Encoder" => "3.002",
    "Test::Deep::NoTest" => 0,
    "XSLoader" => 0,
    "autodie" => 0,
    "bytes" => 0,
    "constant" => 0,
    "namespace::autoclean" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "test_requires" => {
    "Data::Printer" => 0,
    "Devel::Refcount" => 0,
    "ExtUtils::MakeMaker" => 0,
    "File::Spec" => 0,
    "File::Temp" => 0,
    "JSON" => 0,
    "List::AllUtils" => 0,
    "List::Util" => 0,
    "MaxMind::DB::Reader" => 0,
    "Net::Works::Address" => 0,
    "Scalar::Util" => 0,
    "Test::Bits" => 0,
    "Test::Builder" => 0,
    "Test::Fatal" => 0,
    "Test::HexDifferences" => 0,
    "Test::MaxMind::DB::Common::Data" => 0,
    "Test::More" => "0.96",
    "Test::Requires" => 0,
    "Test::Warnings" => 0,
    "lib" => 0,
    "utf8" => 0
  }
);

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
