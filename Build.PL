use strict;
use warnings;

use lib 'inc';

use Config::AutoConf;
use Module::Build;

my $mb = Module::Build->new(
    _mb_args(),
    c_source => 'c',
);

$mb->extra_compiler_flags(
    @{ $mb->extra_compiler_flags },
    qw(-std=c99 -fms-extensions -Wall -g)
);

_check_c_prereqs($mb);

$mb->create_build_script();

sub _mb_args {
    # This is a funky way of allowing this code to run stand-alone and as a
    # template to be processes by Dist::Zilla::Plugin::ModuleBuild::Custom
    my $data = do { local $/; <DATA> };

    if ( $data !~ /^\#/ ) {
        my $args = eval $data;
        return %{$args};
    }
    else {
        return (
            module_name          => 'MaxMind::DB::Writer',
            dist_abstract        => 'Whatever',
            dist_version         => '42',
            license              => 'perl',
            recursive_test_files => 1,
        );
    }
}

sub _check_c_prereqs {
    my $mb = shift;

    my @include_dirs = map { my $dir = $_; $dir =~ s/^-I//; $dir }
        grep { /^-I/ } @{ $mb->extra_compiler_flags() || [] };
    my @lib_dirs = grep { /^-L/ } @{ $mb->extra_linker_flags() || [] };

    my $ac = Config::AutoConf->new(
        extra_include_dirs => \@include_dirs,
        extra_link_flags   => \@lib_dirs,
    );

    if ($ac->check_type('unsigned __int128')) {
        1;
    }
    elsif ( $ac->check_type('unsigned int __attribute__ ((__mode__ (TI)))') ) {
        $mb->extra_compiler_flags(
            @{ $mb->extra_compiler_flags || [] },
            '-DMMDBW_UINT128_USING_MODE',
        );
    }
    elsif ( !$ac->check_type('unsigned __int128') ) {
        warn <<'EOF';

  It looks like your compiler doesn't support the "unsigned __int128" or
  "unsigned int __attribute__ ((__mode__ (TI)))" types. One of these types is
  necessary to compile the MaxMind::DB::Reader::XS module.

EOF

        exit 1;
    }

    return;
}

__DATA__
##{ ( my $args = Data::Dumper::Dumper( $plugin->module_build_args ) ) =~ s/\$VAR\d+ =//; $args ##}
