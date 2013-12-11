package Config::AutoConf;
use ExtUtils::CBuilder;
use 5.008002;

use Config;
use Carp qw/croak/;

use File::Temp qw/tempfile/;
use File::Basename;
use File::Spec;

use Capture::Tiny qw/capture/;
use Scalar::Util qw/looks_like_number/; # in core since 5.7.3

use base 'Exporter';

our @EXPORT = ('$LIBEXT', '$EXEEXT');

use warnings;
use strict;

# XXX detect HP-UX / HPPA
our $LIBEXT = (defined $Config{dlext}) ? ("." . $Config{dlext}) : ($^O =~ /darwin/i)  ? ".dylib" : ( ($^O =~ /mswin32/i) ? ".dll" : ".so" );
our $EXEEXT = ($^O =~ /mswin32/i) ? ".exe" : "";

=encoding UTF-8

=head1 NAME

Config::AutoConf - A module to implement some of AutoConf macros in pure perl.

=cut

our $VERSION = '0.22';

=head1 ABSTRACT

With this module I pretend to simulate some of the tasks AutoConf
macros do. To detect a command, to detect a library, etc.

=head1 SYNOPSIS

    use Config::AutoConf;

    Config::AutoConf->check_prog("agrep");
    my $grep = Config::AutoConf->check_progs("agrep", "egrep", "grep");

    Config::AutoConf->check_header("ncurses.h");
    my $curses = Config::AutoConf->check_headers("ncurses.h","curses.h");

    Config::AutoConf->check_prog_awk;
    Config::AutoConf->check_prog_egrep;

    Config::AutoConf->check_cc();

    Config::AutoConf->check_lib("ncurses", "tgoto");

    Config::AutoConf->check_file("/etc/passwd"); # -f && -r

=head1 FUNCTIONS

=cut

my $glob_instance;

=head2 new

This function instantiates a new instance of Config::AutoConf, eg. to
configure child components.

=cut

sub new {
  my $class = shift;
  ref $class and $class = ref $class;
  my %args = @_;

  my %instance = (
    msg_prefix => 'configure: ',
    lang => "C",
    lang_stack => [],
    lang_supported => {
      "C" => "ExtUtils::CBuilder",
    },
    cache => {},
    defines => {},
    extra_libs => [],
    extra_lib_dirs => [],
    extra_include_dirs => [],
    extra_preprocess_flags => [],
    extra_compile_flags => {
      "C" => [],
    },
    extra_link_flags => [],
    logfile => "config.log",
    %args
  );
  my $self = bless( \%instance, $class );

  return $self;
}

=head2 check_file

This function checks if a file exists in the system and is readable by
the user. Returns a boolean. You can use '-f $file && -r $file' so you
don't need to use a function call.

=cut

sub check_file {
  my $self = shift;
  my $file = shift;

  return (-f $file && -r $file);
}


=head2 check_files

This function checks if a set of files exist in the system and are
readable by the user. Returns a boolean.

=cut

sub check_files {
  my $self = shift;

  for (@_) {
    return 0 unless check_file($self, $_)
  }

  return 1;
}


=head2 check_prog

This function checks for a program with the supplied name. In success
returns the full path for the executable;

=cut

sub check_prog {
  my $self = shift;
  # sanitize ac_prog
  my $ac_prog = _sanitize(shift());
  my $PATH = $ENV{PATH};
  my $p;

	my $ext = "";
	$ext = ".exe" if $^O =~ /mswin/i;
	
  for $p (split /$Config{path_sep}/,$PATH) {
    my $cmd = File::Spec->catfile($p,$ac_prog.$ext);
    return $cmd if -x $cmd;
  }
  return undef;
}

=head2 check_progs

This function takes a list of program names. Returns the full path for
the first found on the system. Returns undef if none was found.

=cut

sub check_progs {
  my $self = shift;
  my @progs = @_;
  for (@progs) {
    my $ans = check_prog($self, $_);
    return $ans if $ans;
  }
  return undef;
}

=head2 check_prog_yacc

From the autoconf documentation,

  If `bison' is found, set [...] `bison -y'.
  Otherwise, if `byacc' is found, set [...] `byacc'. 
  Otherwise set [...] `yacc'.

Returns the full path, if found.

=cut

sub check_prog_yacc {
	my $self = shift;
	my $binary = check_progs(qw/$self bison byacc yacc/);
	$binary .= " -y" if ($binary =~ /bison$/);
	return $binary;
}

=head2 check_prog_awk

From the autoconf documentation,

  Check for `gawk', `mawk', `nawk', and `awk', in that order, and
  set output [...] to the first one that is found.  It tries
  `gawk' first because that is reported to be the best
  implementation.

Note that it returns the full path, if found.

=cut

sub check_prog_awk {
  my $self = shift;
  return check_progs(qw/$self gawk mawk nawk awk/);
}


=head2 check_prog_egrep

From the autoconf documentation,

  Check for `grep -E' and `egrep', in that order, and [...] output
  [...] the first one that is found.

Note that it returns the full path, if found.

=cut

sub check_prog_egrep {
  my $self = shift;

  my $grep;

  if ($grep = check_prog($self,"grep")) {
    my $ans = `echo a | ($grep -E '(a|b)') 2>/dev/null`;
    return "$grep -E" if $ans eq "a\n";
  }

  if ($grep = check_prog($self, "egrep")) {
    return $grep;
  }
  return undef;
}

=head2 check_cc

This function checks if you have a running C compiler.

=cut

sub check_cc {
  ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
}

=head2 msg_checking

Prints "Checking @_ ..."

=cut

sub msg_checking {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print "Checking " . join(" ", @_) . "... ";
  $self->_add2log( "Checking " . join( " ", @_, "..." ) );
  return;
}

=head2 msg_result

Prints result \n

=cut

sub msg_result {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print join( " ", map { looks_like_number( $_ ) ? ( $_ == 0 ? "no" : ( $_ == 1 ? "yes" : $_ ) ) : $_ } @_ ), "\n";
  return;
}

=head2 msg_notice

Prints "configure: " @_ to stdout

=cut

sub msg_notice {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print $self->{msg_prefix} . join( " ", @_ ) . "\n";
  return;
}

=head2 msg_warn

Prints "configure: " @_ to stderr

=cut

sub msg_warn {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print STDERR $self->{msg_prefix} . join( " ", @_ ) . "\n";
  return;
}

=head2 msg_error

Prints "configure: " @_ to stderr and exits with exit code 0 (tells
toolchain to stop here and report unsupported environment)

=cut

sub msg_error {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print STDERR $self->{msg_prefix} . join( " ", @_ ) . "\n";
  exit(0); # #toolchain agreement: prevents configure stage to finish
}

=head2 msg_failure

Prints "configure: " @_ to stderr and exits with exit code 0 (tells
toolchain to stop here and report unsupported environment). Additional
details are provides in config.log (probably more information in a
later stage).

=cut

sub msg_failure {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print STDERR $self->{msg_prefix} . join( " ", @_ ) . "\n";
  exit(0); # #toolchain agreement: prevents configure stage to finish
}

=head2 define_var( $name, $value [, $comment ] )

Defines a check variable for later use in further checks or code to compile.

=cut

sub define_var {
  my $self = shift->_get_instance();
  my ($name, $value, $comment) = @_;

  defined( $name ) or croak( "Need a name to add a define" );

  $self->{defines}->{$name} = [ $value, $comment ];

  return;
}

=head2 write_config_h( [$target] )

Writes the defined constants into given target:

  Config::AutoConf->write_config_h( "config.h" );

=cut

sub write_config_h {
  my $self = shift->_get_instance();
  my $tgt;
  
  defined( $_[0] )
    ? ( ref( $_[0] )
      ? $tgt = $_[0]
      : open( $tgt, ">", $_[0] ) )
    : open( $tgt, ">", "config.h" );

  my $conf_h = <<'EOC';
/**
 * Generated from Config::AutoConf
 *
 * Do not edit this file, all modifications will be lost,
 * modify Makefile.PL or Build.PL instead.
 *
 * Inspired by GNU AutoConf.
 *
 * (c) 2011 Alberto Simoes & Jens Rehsack
 */
#ifndef __CONFIG_H__

EOC

  while( my ($defname, $defcnt) = each( %{ $self->{defines} } ) ) {
    if( $defcnt->[0] ) {
      defined $defcnt->[1] and $conf_h .= "/* " . $defcnt->[1] . " */\n";
      $conf_h .= join( " ", "#define", $defname, $defcnt->[0] ) . "\n";
    }
    else {
      defined $defcnt->[1] and $conf_h .= "/* " . $defcnt->[1] . " */\n";
      $conf_h .= "/* " . join( " ", "#undef", $defname ) . " */\n\n";
    }
  }
  $conf_h .= "#endif /* ?__CONFIG_H__ */\n";

  print {$tgt} $conf_h;

  return;
}

=head2 push_lang(lang [, implementor ])

Puts the current used language on the stack and uses specified language
for subsequent operations until ending pop_lang call.

=cut

sub push_lang {
  my $self = shift->_get_instance();

  push @{$self->{lang_stack}}, [ $self->{lang} ];

  return $self->_set_language( @_ );
}

=head2 pop_lang([ lang ])

Pops the currently used language from the stack and restores previously used
language. If I<lang> specified, it's asserted that the current used language
equals to specified language (helps finding control flow bugs).

=cut

sub pop_lang {
  my $self = shift->_get_instance();

  scalar( @{$self->{lang_stack}} ) > 0 or croak( "Language stack empty" );
  defined( $_[0] ) and $self->{lang} ne $_[0] and
    croak( "pop_lang( $_[0] ) doesn't match language in use (" . $self->{lang} . ")" );

  return $self->_set_language( @{ pop @{ $self->{lang} } } );
}

=head2 lang_call( [prologue], function )

Builds program which simply calls given function.
When given, prologue is prepended otherwise, the default
includes are used.

=cut

sub lang_call {
  my $self = shift->_get_instance();
  my ($prologue, $function) = @_;

  defined( $prologue ) or $prologue = $self->_default_includes();
  $prologue .= <<"_ACEOF";
/* Override any GCC internal prototype to avoid an error.
   Use char because int might match the return type of a GCC
   builtin and then its argument prototype would still apply.  */
#ifdef __cplusplus
extern "C" {
#endif
char $function ();
#ifdef __cplusplus
}
#endif
_ACEOF
  my $body = "return $function ();";
  $body = $self->_build_main( $body );

  my $conftest  = $self->_fill_defines();
     $conftest .= "\n$prologue\n";
     $conftest .= "\n$body\n";

  return $conftest;
}

=head2 lang_build_program( prologue, body )

Builds program for current chosen language. If no prologue is given
(I<undef>), the default headers are used. If body is missing, default
body is used.

Typical call of

  Config::AutoConf->lang_build_program( "const char hw[] = \"Hello, World\\n\";",
                                        "fputs (hw, stdout);" )

will create

  const char hw[] = "Hello, World\n";

  /* Override any gcc2 internal prototype to avoid an error.  */
  #ifdef __cplusplus
  extern "C" {
  #endif

  int
  main (int argc, char **argv)
  {
    (void)argc;
    (void)argv;
    fputs (hw, stdout);;
    return 0;
  }

  #ifdef __cplusplus
  }
  #endif

=cut

sub lang_build_program {
  my $self = shift->_get_instance();
  my ($prologue, $body) = @_;

  defined( $prologue ) or $prologue = $self->_default_includes();
  defined( $body ) or $body = "";
  $body = $self->_build_main( $body );

  my $conftest  = $self->_fill_defines();
     $conftest .= "\n$prologue\n";
     $conftest .= "\n$body\n";

  return $conftest;
}

=head2 lang_build_bool_test (prologue, test, [@decls])

Builds a static test which will fail to compile when test
evaluates to false. If C<@decls> is given, it's prepended
before the test code at the variable definition place.

=cut

sub lang_build_bool_test {
  my $self = shift->_get_instance();
  my ($prologue, $test, @decls) = @_;

  defined( $test ) or $test = "1";
  my $test_code = <<ACEOF;
  static int test_array [($test) ? 1 : -1 ];
  test_array [0] = 0
ACEOF
  if( @decls ) {
    $test_code = join( "\n", @decls, $test_code );
  }
  return $self->lang_build_program( $prologue, $test_code );
}

=head2 push_includes

Adds given list of directories to preprocessor/compiler
invocation. This is not proved to allow adding directories
which might be created during the build.

=cut

sub push_includes {
  my $self = shift->_get_instance();
  my @includes = @_;

  push( @{$self->{extra_include_dirs}}, @includes );

  return;
}

=head2 push_preprocess_flags

Adds given flags to the parameter list for preprocessor invocation.

=cut

sub push_preprocess_flags {
  my $self = shift->_get_instance();
  my @cpp_flags = @_;

  push( @{$self->{extra_preprocess_flags}}, @cpp_flags );

  return;
}

=head2 push_compiler_flags

Adds given flags to the parameter list for compiler invocation.

=cut

sub push_compiler_flags {
  my $self = shift->_get_instance();
  my @compiler_flags = @_;
  my $lang = $self->{lang};

  if( scalar( @compiler_flags ) && ( ref($compiler_flags[-1]) eq "HASH" ) ) {
    my $lang_opt = pop( @compiler_flags );
    defined( $lang_opt->{lang} ) or croak( "Missing lang attribute in language options" );
    $lang = $lang_opt->{lang};
    defined( $self->{lang_supported}->{$lang} ) or croak( "Unsupported language '$lang'" );
  }

  push( @{$self->{extra_compile_flags}->{$lang}}, @compiler_flags );

  return;
}

=head2 push_libraries

Adds given list of libraries to the parameter list for linker invocation.

=cut

sub push_libraries {
  my $self = shift->_get_instance();
  my @libs = @_;

  push( @{$self->{extra_libs}}, @libs );

  return;
}

=head2 push_library_paths

Adds given list of library paths to the parameter list for linker invocation.

=cut

sub push_library_paths {
  my $self = shift->_get_instance();
  my @libdirs = @_;

  push( @{$self->{extra_lib_dirs}}, @libdirs );

  return;
}

=head2 push_link_flags

Adds given flags to the parameter list for linker invocation.

=cut

sub push_link_flags {
  my $self = shift->_get_instance();
  my @link_flags = @_;

  push( @{$self->{extra_link_flags}}, @link_flags );

  return;
}

=head2 compile_if_else( $src [, action-if-true [, action-if-false ] ] )

This function trys to compile specified code and runs action-if-true on success
or action-if-false otherwise.

Returns a boolean value containing check success state.

=cut

sub compile_if_else {
  my ($self, $src, $action_if_true, $action_if_false) = @_;
  ref $self or $self = $self->_get_instance();
  my $builder = $self->_get_builder();

  my ($fh, $filename) = tempfile( "testXXXXXX", SUFFIX => '.c');

  print {$fh} $src;
  close $fh;

  my ($obj_file, $errbuf, $exception);
  (undef, $errbuf) = capture {
    eval {
      $obj_file = $builder->compile(
        source => $filename,
        include_dirs => $self->{extra_include_dirs},
        extra_compiler_flags => $self->_get_extra_compiler_flags() );
    };

    $exception = $@;
  };

  unlink $filename;
  unlink $obj_file if $obj_file;

  if ($exception || !$obj_file) {
    $self->_add2log( "compile stage failed" . ( $exception ? " - " . $exception : "" ) );
    $errbuf and
      $self->_add2log( $errbuf );
    $self->_add2log( "failing program is:\n" . $src );

    defined( $action_if_false ) and "CODE" eq ref( $action_if_false ) and &{$action_if_false}();
    return 0;
  }

  defined( $action_if_true ) and "CODE" eq ref( $action_if_true ) and &{$action_if_true}();
  return 1;
}

=head2 link_if_else( $src [, action-if-true [, action-if-false ] ] )

This function trys to compile and link specified code and runs action-if-true on success
or action-if-false otherwise.

Returns a boolean value containing check success state.

=cut

sub link_if_else {
  my ($self, $src, $action_if_true, $action_if_false) = @_;
  ref $self or $self = $self->_get_instance();
  my $builder = $self->_get_builder();

  my ($fh, $filename) = tempfile( "testXXXXXX", SUFFIX => '.c');

  print {$fh} $src;
  close $fh;

  my ($obj_file, $errbuf, $exception);
  (undef, $errbuf) = capture {
    eval {
      $obj_file = $builder->compile(
        source => $filename,
        include_dirs => $self->{extra_include_dirs},
        extra_compiler_flags => $self->_get_extra_compiler_flags() );
    };

    $exception = $@;
  };

  if ($exception || !$obj_file) {
    $self->_add2log( "compile stage failed" . ( $exception ? " - " . $exception : "" ) );
    $errbuf and
      $self->_add2log( $errbuf );
    $self->_add2log( "failing program is:\n" . $src );

    unlink $filename;
    unlink $obj_file if $obj_file;
    defined( $action_if_false ) and "CODE" eq ref( $action_if_false ) and &{$action_if_false}();
    return 0;
  }

  my $exe_file;
  (undef, $errbuf) = capture {
    eval {
      $exe_file = $builder->link_executable(
        objects => $obj_file,
        extra_linker_flags => $self->_get_extra_linker_flags() );
    };

    $exception = $@;
  };
  unlink $filename;
  unlink $obj_file if $obj_file;
  unlink $exe_file if $exe_file;

  if ($exception || !$exe_file) {
    $self->_add2log( "link stage failed" . ( $exception ? " - " . $exception : "" ) );
    $errbuf and
      $self->_add2log( $errbuf );
    $self->_add2log( "failing program is:\n" . $src );

    defined( $action_if_false ) and "CODE" eq ref( $action_if_false ) and &{$action_if_false}();
    return 0;
  }

  defined( $action_if_true ) and "CODE" eq ref( $action_if_true ) and &{$action_if_true}();
  return 1;
}

=head2 check_cached( cache-var, message, sub-to-check )

This function checks whether a specified cache variable is set or not, and if not
it's going to set it using specified sub-to-check.

=cut

sub check_cached {
  my ($self, $cache_name, $message, $check_sub) = @_;
  ref $self or $self = $self->_get_instance();

  $self->msg_checking( $message );

  if( defined($self->{cache}->{$cache_name}) ) {
    $self->msg_result( "(cached)", $self->{cache}->{$cache_name} );
  }
  else {
    $self->{cache}->{$cache_name} = &{$check_sub}();
    $self->msg_result( $self->{cache}->{$cache_name} );
  }

  return $self->{cache}->{$cache_name};
}

=head2 cache_val

This functions returns the value of a previously check_cached call.

=cut

sub cache_val {
  my $self = shift->_get_instance();
  my $cache_name = shift;
  defined $self->{cache}->{$cache_name} or return;
  return $self->{cache}->{$cache_name};
}

=head2 check_decl( symbol, [action-if-found], [action-if-not-found], [prologue = default includes] )

If symbol (a function, variable or constant) is not declared in includes and
a declaration is needed, run the code ref given in I<action-if-not-found>,
otherwise I<action-if-found>. includes is a series of include directives,
defaulting to I<default includes>, which are used prior to the declaration
under test.

This method actually tests whether symbol is defined as a macro or can be
used as an r-value, not whether it is really declared, because it is much
safer to avoid introducing extra declarations when they are not needed.
In order to facilitate use of C++ and overloaded function declarations, it
is possible to specify function argument types in parentheses for types
which can be zero-initialized:

          Config::AutoConf->check_decl("basename(char *)")

This method caches its result in the C<ac_cv_decl_E<lt>set langE<gt>>_symbol variable.

=cut

sub check_decl {
  my ($self, $symbol, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $symbol ) or return; # XXX prefer croak
  ref( $symbol ) eq "" or return;
  ( my $sym_plain = $symbol ) =~ s/ *\(.*//;
  my $sym_call = $symbol;
  $sym_call =~ s/\(/((/;
  $sym_call =~ s/\)/) 0)/;
  $sym_call =~ s/,/) 0, (/g;

  my $cache_name = $self->_cache_name( "decl", $self->{lang}, $symbol );
  my $check_sub = sub {
  
    my $body = <<ACEOF;
#ifndef $sym_plain
  (void) $sym_call;
#endif
ACEOF
    my $conftest = $self->lang_build_program( $prologue, $body );

    my $have_decl = $self->compile_if_else( $conftest );
    if( $have_decl ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $have_decl;
  };

  return $self->check_cached( $cache_name, "whether $symbol is declared", $check_sub );
}

=head2 check_decls( symbols, [action-if-found], [action-if-not-found], [prologue = default includes] )

For each of the symbols (with optional function argument types for C++
overloads), run L<check_decl>. If I<action-if-not-found> is given, it
is additional code to execute when one of the symbol declarations is
needed, otherwise I<action-if-found> is executed.

Contrary to GNU autoconf, this method does not declare HAVE_DECL_symbol
macros for the resulting C<confdefs.h>, because it differs as C<check_decl>
between compiling languages.

=cut

sub check_decls {
  my ($self, $symbols, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_syms = 1;
  foreach my $symbol (@$symbols) {
    $have_syms &= $self->check_decl( $symbol, undef, undef, $prologue );
  }

  if( $have_syms ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  return $have_syms;
}

sub _have_type_define_name {
  my $type = $_[0];
  my $have_name = "HAVE_" . uc($type);
  $have_name =~ tr/*/P/;
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

=head2 check_type (type, [action-if-found], [action-if-not-found], [prologue = default includes])

Check whether type is defined. It may be a compiler builtin type or defined
by the includes. I<prologue> should be a series of include directives,
defaulting to I<default includes>, which are used prior to the type under
test.

In C, type must be a type-name, so that the expression C<sizeof (type)> is
valid (but C<sizeof ((type))> is not)

If I<type> type is defined, preprocessor macro HAVE_I<type> (in all
capitals, with "*" replaced by "P" and spaces and dots replaced by
underscores) is defined.

This method caches its result in the C<ac_cv_type_>type variable.

=cut

sub check_type {
  my ($self, $type, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $type ) or return; # XXX prefer croak
  ref( $type ) eq "" or return;

  my $cache_name = $self->_cache_type_name( "type", $type );
  my $check_sub = sub {
  
    my $body = <<ACEOF;
  if( sizeof ($type) )
    return 0;
ACEOF
    my $conftest = $self->lang_build_program( $prologue, $body );

    my $have_type = $self->compile_if_else( $conftest );
    $self->define_var( _have_type_define_name( $type ), $have_type ? $have_type : undef, "defined when $type is available" );
    if( $have_type ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $have_type;
  };

  return $self->check_cached( $cache_name, "for $type", $check_sub );
}

=head2 check_types (types, [action-if-found], [action-if-not-found], [prologue = default includes])

For each type L<check_type> is called to check for type.

If I<action-if-found> is given, it is additionally executed when all of the
types are found. If I<action-if-not-found> is given, it is executed when one
of the types is not found.

=cut

sub check_types {
  my ($self, $types, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_types = 1;
  foreach my $type (@$types) {
    $have_types &= $self->check_type( $type, undef, undef, $prologue );
  }

  if( $have_types ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  return $have_types;
}

sub _compute_int_compile {
  my ($self, $expr, $prologue, @decls) = @_;
  $self = $self->_get_instance();

  my( $body, $conftest, $compile_result );

  my ($low, $mid, $high) = (0, 0, 0);
  if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) >= 0", @decls ) ) ) {
    $low = $mid = 0;
    while( 1 ) {
      if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) <= $mid", @decls ) ) ) {
	$high = $mid;
	last;
      }
      $low = $mid + 1;
      # avoid overflow
      if( $low <= $mid ) {
	$low = 0;
	last;
      }
      $mid = $low * 2;
    }
  }
  elsif( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) < 0", @decls ) ) ) {
    $high = $mid = -1;
    while( 1 ) {
      if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) >= $mid", @decls ) ) ) {
	$low = $mid;
	last;
      }
      $high = $mid - 1;
      # avoid overflow
      if( $mid < $high ) {
	$high = 0;
	last;
      }
      $mid = $high * 2;
    }
  }

  # perform binary search between $low and $high
  while( $low <= $high ) {
    $mid = int( ( $high - $low ) / 2 + $low );
    if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) < $mid", @decls ) ) ) {
      $high = $mid - 1;
    }
    elsif( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) > $mid", @decls ) ) ) {
      $low = $mid + 1;
    }
    else {
      return $mid;
    }
  }

  return;
}

=head2 compute_int (expression, [action-if-fails], [prologue = default includes], [@decls])

Returns the value of the integer I<expression>. The value should fit in an
initializer in a C variable of type signed long.  It should be possible
to evaluate the expression at compile-time. If no includes are specified,
the default includes are used.

Execute I<action-if-fails> if the value cannot be determined correctly.

=cut

sub compute_int {
  my ($self, $expr, $action_if_fails, $prologue, @decls) = @_;
  $self = $self->_get_instance();

  my $cache_name = $self->_cache_type_name( "compute_int", $self->{lang}, $expr );
  my $check_sub = sub {

    my $val = $self->_compute_int_compile( $expr, $prologue, @decls);
    unless( defined( $val ) ) {
      if( defined( $action_if_fails ) and "CODE" eq ref( $action_if_fails ) ) {
	&{$action_if_fails}();
      }
    }

    return $val;
  };

  return $self->check_cached( $cache_name, "for compute result of ($expr)", $check_sub );
}

sub _sizeof_type_define_name {
  my $type = $_[0];
  my $have_name = "SIZEOF_" . uc($type);
  $have_name =~ tr/*/P/;
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

=head2 check_sizeof_type (type, [action-if-found], [action-if-not-found], [prologue = default includes])

Checks for the size of the specified type by compiling. If no size can
determined, I<action-if-not-found> is invoked when given. Otherwise
I<action-if-found> is invoked and C<SIZEOF_type> is defined using the
determined size.

In opposition to GNU AutoConf, this method can determine size of structure
members, eg.

  $ac->check_sizeof_type( "SV.sv_refcnt", undef, undef, $include_perl );
  # or
  $ac->check_sizeof_type( "struct utmpx.ut_id", undef, undef, "#include <utmpx.h>" );

This method caches its result in the C<ac_cv_sizeof_E<lt>set langE<gt>>_type variable.

=cut

sub check_sizeof_type {
  my ($self, $type, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $type ) or return; # XXX prefer croak
  ref( $type ) eq "" or return;

  my $cache_name = $self->_cache_type_name( "sizeof", $self->{lang}, $type );
  my $check_sub = sub {

    my @decls;
    if( $type =~ m/^([^.]+)\.([^.]+)$/ ) {
      my $struct = $1;
      $type = "_ac_test_aggr.$2";
      my $decl = "static $struct _ac_test_aggr;";
      push( @decls, $decl );
    }
  
    my $typesize = $self->_compute_int_compile( "sizeof($type)", $prologue, @decls );
    $self->define_var( _sizeof_type_define_name( $type ), $typesize ? $typesize : undef, "defined when sizeof($type) is available" );
    if( $typesize ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $typesize;
  };

  return $self->check_cached( $cache_name, "for size of $type", $check_sub );
}

=head2 check_sizeof_types (type, [action-if-found], [action-if-not-found], [prologue = default includes])

For each type L<check_sizeof_type> is called to check for size of type.

If I<action-if-found> is given, it is additionally executed when all of the
sizes of the types could determined. If I<action-if-not-found> is given, it
is executed when one size of the types could not determined.

=cut

sub check_sizeof_types {
  my ($self, $types, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_sizes = 1;
  foreach my $type (@$types) {
    $have_sizes &= ! ! ($self->check_sizeof_type ( $type, undef, undef, $prologue ));
  }

  if( $have_sizes ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  return $have_sizes;
}

sub _alignof_type_define_name {
  my $type = $_[0];
  my $have_name = "ALIGNOF_" . uc($type);
  $have_name =~ tr/*/P/;
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

=head2 check_alignof_type (type, [action-if-found], [action-if-not-found], [prologue = default includes])

Define ALIGNOF_type to be the alignment in bytes of type. I<type y;> must
be valid as a structure member declaration or I<type> must be a structure
member itself.

This method caches its result in the C<ac_cv_alignof_E<lt>set langE<gt>>_type
variable, with I<*> mapped to C<p> and other characters not suitable for a
variable name mapped to underscores.

=cut

sub check_alignof_type {
  my ($self, $type, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $type ) or return; # XXX prefer croak
  ref( $type ) eq "" or return;

  my $cache_name = $self->_cache_type_name( "alignof", $self->{lang}, $type );
  my $check_sub = sub {

    my @decls = (
      "#ifndef offsetof",
      "# ifdef __ICC",
      "#  define offsetof(type,memb) ((size_t)(((char *)(&((type*)0)->memb)) - ((char *)0)))",
      "# else",
      "#  define offsetof(type,memb) ((size_t)&((type*)0)->memb)",
      "# endif",
      "#endif"
    );

    my ($struct, $memb);
    if( $type =~ m/^([^.]+)\.([^.]+)$/ ) {
      $struct = $1;
      $memb = $2;
    }
    else {
      push( @decls, "typedef struct { char x; $type y; } ac__type_alignof_;" );
      $struct = "ac__type_alignof_";
      $memb = "y";
    }
  
    my $typealign = $self->_compute_int_compile( "offsetof($struct, $memb)", $prologue, @decls );
    $self->define_var( _alignof_type_define_name( $type ), $typealign ? $typealign : undef, "defined when alignof($type) is available" );
    if( $typealign ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $typealign;
  };

  return $self->check_cached( $cache_name, "for align of $type", $check_sub );
}

=head2 check_alignof_types (type, [action-if-found], [action-if-not-found], [prologue = default includes])

For each type L<check_alignof_type> is called to check for align of type.

If I<action-if-found> is given, it is additionally executed when all of the
aligns of the types could determined. If I<action-if-not-found> is given, it
is executed when one align of the types could not determined.

=cut

sub check_alignof_types {
  my ($self, $types, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_aligns = 1;
  foreach my $type (@$types) {
    $have_aligns &= ! ! ($self->check_alignof_type ( $type, undef, undef, $prologue ));
  }

  if( $have_aligns ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  return $have_aligns;
}

sub _have_member_define_name {
  my $member = $_[0];
  my $have_name = "HAVE_" . uc($member);
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

=head2 check_member (member, [action-if-found], [action-if-not-found], [prologue = default includes])

Check whether I<member> is in form of I<aggregate>.I<member> and
I<member> is a member of the I<aggregate> aggregate. I<prologue>
should be a series of include directives, defaulting to
I<default includes>, which are used prior to the aggregate under test.

  Config::AutoConf->check_member(
    "struct STRUCT_SV.sv_refcnt",
    undef,
    sub { Config::AutoConf->msg_failure( "sv_refcnt member required for struct STRUCT_SV" ); }
    "#include <EXTERN.h>\n#include <perl.h>"
  );

If I<aggregate> aggregate has I<member> member, preprocessor
macro HAVE_I<aggregate>_I<MEMBER> (in all capitals, with spaces
and dots replaced by underscores) is defined.

This macro caches its result in the C<ac_cv_>aggr_member variable.

=cut

sub check_member {
  my ($self, $member, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $member ) or return; # XXX prefer croak
  ref( $member ) eq "" or return;

  $member =~ m/^([^.]+)\.([^.]+)$/ or return;
  my $type = $1;
  $member = $2;

  my $cache_name = $self->_cache_type_name( "member", $type );
  my $check_sub = sub {
  
    my $body = <<ACEOF;
  static $type check_aggr;
  if( check_aggr.$member )
    return 0;
ACEOF
    my $conftest = $self->lang_build_program( $prologue, $body );

    my $have_member = $self->compile_if_else( $conftest );
    $self->define_var( _have_member_define_name( $member ), $have_member ? $have_member : undef, "defined when $member is available" );
    if( $have_member ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $have_member;
  };

  return $self->check_cached( $cache_name, "for $type.$member", $check_sub );
}

=head2 check_members (members, [action-if-found], [action-if-not-found], [prologue = default includes])

For each member L<check_member> is called to check for member of aggregate.

If I<action-if-found> is given, it is additionally executed when all of the
aggregate members are found. If I<action-if-not-found> is given, it is
executed when one of the aggregate members is not found.

=cut

sub check_members {
  my ($self, $members, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_members = 1;
  foreach my $member (@$members) {
    $have_members &= $self->check_member( $member, undef, undef, $prologue );
  }

  if( $have_members ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  return $have_members;
}

=head2 check_headers

This function uses check_header to check if a set of include files exist in the system and can
be included and compiled by the available compiler. Returns the name of the first header file found.

=cut

sub check_headers {
  my $self = shift;

  for (@_) {
    return $_ if check_header($self, $_)
  }

  return undef;
}

sub _have_header_define_name {
  my $header = $_[0];
  my $have_name = "HAVE_" . uc($header);
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

sub _check_header {
  my ($self, $header, $prologue, $body) = @_;

  $prologue .= <<"_ACEOF";
    #include <$header>
_ACEOF
  my $conftest = $self->lang_build_program( $prologue, $body );

  my $have_header = $self->compile_if_else( $conftest );
  return $have_header;
}


=head2 check_header

This function is used to check if a specific header file is present in
the system: if we detect it and if we can compile anything with that
header included. Note that normally you want to check for a header
first, and then check for the corresponding library (not all at once).

The standard usage for this module is:

  Config::AutoConf->check_header("ncurses.h");
  
This function will return a true value (1) on success, and a false value
if the header is not present or not available for common usage.

=cut

sub check_header {
  my $self = shift;
  my $header = shift;
  my $pre_inc = shift;
  

  return 0 unless $header;
  my $prologue  = "";
  defined $pre_inc
    and $prologue .= "$pre_inc\n";

  my $cache_name = $self->_cache_name( $header );
  my $check_sub = sub {
  
    my $have_header = $self->_check_header( $header, $prologue, "" );
    $self->define_var( _have_header_define_name( $header ), $have_header ? $have_header : undef, "defined when $header is available" );

    return $have_header;
  };

  return $self->check_cached( $cache_name, "for $header", $check_sub );
}

=head2 check_all_headers

This function checks each given header for usability.

=cut

sub check_all_headers {
  my $self = shift->_get_instance();
  @_ or return;
  my $rc = 1;
  foreach my $header (@_) {
    $rc &= $self->check_header( $header );
  }
  return $rc;
}

=head2 check_stdc_headers

Checks for standard C89 headers, namely stdlib.h, stdarg.h, string.h and float.h.
If those are found, additional all remaining C89 headers are checked: assert.h,
ctype.h, errno.h, limits.h, locale.h, math.h, setjmp.h, signal.h, stddef.h,
stdio.h and time.h.

Returns a false value if it fails.

=cut

sub check_stdc_headers {
  my $self = shift->_get_instance();
  my $rc = 0;
  if( $rc = $self->check_all_headers( qw(stdlib.h stdarg.h string.h float.h) ) ) {
    $rc &= $self->check_all_headers( qw/assert.h ctype.h errno.h limits.h/ );
    $rc &= $self->check_all_headers( qw/locale.h math.h setjmp.h signal.h/ );
    $rc &= $self->check_all_headers( qw/stddef.h stdio.h time.h/ );
  }
  if( $rc ) {
    $self->define_var( "STDC_HEADERS", 1, "Define to 1 if you have the ANSI C header files." );
  }
  return $rc;
}

=head2 check_default_headers

This function checks for some default headers, the std c89 haeders and
sys/types.h, sys/stat.h, memory.h, strings.h, inttypes.h, stdint.h and unistd.h

=cut

sub check_default_headers {
  my $self = shift->_get_instance();
  my $rc = $self->check_stdc_headers() and $self->check_all_headers( qw(sys/types.h sys/stat.h memory.h strings.h inttypes.h stdint.h unistd.h) );
  return $rc;
}

=head2 check_dirent_header

Check for the following header files. For the first one that is found and
defines 'DIR', define the listed C preprocessor macro:

  dirent.h 	HAVE_DIRENT_H
  sys/ndir.h 	HAVE_SYS_NDIR_H
  sys/dir.h 	HAVE_SYS_DIR_H
  ndir.h 	HAVE_NDIR_H

The directory-library declarations in your source code should look
something like the following:

  #include <sys/types.h>
  #ifdef HAVE_DIRENT_H
  # include <dirent.h>
  # define NAMLEN(dirent) strlen ((dirent)->d_name)
  #else
  # define dirent direct
  # define NAMLEN(dirent) ((dirent)->d_namlen)
  # ifdef HAVE_SYS_NDIR_H
  #  include <sys/ndir.h>
  # endif
  # ifdef HAVE_SYS_DIR_H
  #  include <sys/dir.h>
  # endif
  # ifdef HAVE_NDIR_H
  #  include <ndir.h>
  # endif
  #endif

Using the above declarations, the program would declare variables to be of
type C<struct dirent>, not C<struct direct>, and would access the length
of a directory entry name by passing a pointer to a C<struct dirent> to
the C<NAMLEN> macro.

This macro might be obsolescent, as all current systems with directory
libraries have C<<E<lt>dirent.hE<gt>>>. Programs supporting only newer OS
might not need touse this macro.

=cut

sub check_dirent_header {
  my $self = shift->_get_instance();

  my $cache_name = $self->_cache_name( "header_dirent" );
  my $check_sub = sub {

    my $have_dirent;
    foreach my $header (qw(dirent.h sys/ndir.h sys/dir.h ndir.h)) {
      $have_dirent = $self->_check_header( $header, "#include <sys/types.h>\n", "if ((DIR *) 0) { return 0; }" );
      $self->define_var( _have_header_define_name( $header ), $have_dirent ? $have_dirent : undef, "defined when $header is available" );
      $have_dirent and $have_dirent = $header and last;
    }

    return $have_dirent;
  };


  return $self->check_cached( $cache_name, "for header defining DIR *", $check_sub );
}

sub _have_lib_define_name {
  my $lib = $_[0];
  my $have_name = "HAVE_LIB" . uc($lib);
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

=head2 check_lm( [ action-if-found ], [ action-if-not-found ] )

This method is used to check if some common C<math.h> functions are
available, and if C<-lm> is needed. Returns the empty string if no
library is needed, or the "-lm" string if libm is needed.

Actions are only called at the end of the list of tests. If one fails,
I<action-if-not-found> is run. Otherwise, I<action-if-found> is run.

=cut

sub check_lm {
    my ($self, $aif, $ainf) = @_;
    ref($self) or $self = $self->_get_instance();

    my $fail = 0;
    my $required = "";
    for my $func (qw(log2 pow log10 log exp sqrt)) {

        my $ans = $self->search_libs( $func, ['m'] );

        $ans or $fail = 1;
        ($ans ne "none required") and $required = $ans;
    }

    if ($fail) { $ainf && $ainf->() }
    else       { $aif  && $aif->() }

    return $required;
}

=head2 check_lib( lib, func, [ action-if-found ], [ action-if-not-found ], [ @other-libs ] )

This function is used to check if a specific library includes some
function. Call it with the library name (without the lib portion), and
the name of the function you want to test:

  Config::AutoConf->check_lib("z", "gzopen");

It returns 1 if the function exist, 0 otherwise.

I<action-if-found> and I<action-if-not-found> can be CODE references
whereby the default action in case of function found is to define
the HAVE_LIBlibrary (all in capitals) preprocessor macro with 1 and
add $lib to the list of libraries to link.

If linking with library results in unresolved symbols that would be
resolved by linking with additional libraries, give those libraries
as the I<other-libs> argument: e.g., C<[qw(Xt X11)]>.
Otherwise, this routine may fail to detect that library is present,
because linking the test program can fail with unresolved symbols.
The other-libraries argument should be limited to cases where it is
desirable to test for one library in the presence of another that
is not already in LIBS. 

It's recommended to use L<search_libs> instead of check_lib these days.

=cut

sub check_lib {
    my ( $self, $lib, $func, $action_if_found, $action_if_not_found, @other_libs ) = @_;
    ref($self) or $self = $self->_get_instance();

    return 0 unless $lib;
    return 0 unless $func;

    scalar( @other_libs ) == 1 and ref( $other_libs[0] ) eq "ARRAY"
      and @other_libs = @{ $other_libs[0] };

    my $cache_name = $self->_cache_name( "lib", $lib, $func );
    my $check_sub = sub {
        my $conftest = $self->lang_call( "", $func );

        my @save_libs = @{$self->{extra_libs}};
        push( @{$self->{extra_libs}}, $lib, @other_libs );
        my $have_lib = $self->link_if_else( $conftest );
        $self->{extra_libs} = [ @save_libs ];

        if( $have_lib ) {
            if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
                &{$action_if_found}();
            }
            else {
                $self->define_var( _have_lib_define_name( $lib ), $have_lib,
                                   "defined when library $lib is available" );
                push( @{$self->{extra_libs}}, $lib );
            }
        }
        else {
            if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
                &{$action_if_not_found}();
            }
            else {
                $self->define_var( _have_lib_define_name( $lib ), undef,
                                   "defined when library $lib is available" );
            }
        }
        return $have_lib;
    };

    return $self->check_cached( $cache_name, "for $func in -l$lib", $check_sub );
}

=head2 search_libs( function, search-libs, [action-if-found], [action-if-not-found], [other-libs] )

Search for a library defining function if it's not already available.
This equates to calling

    Config::AutoConf->link_if_else(
        Config::AutoConf->lang_call( "", "$function" ) );

first with no libraries, then for each library listed in search-libs.
I<search-libs> must be specified as an array reference to avoid
confusion in argument order.

Prepend -llibrary to LIBS for the first library found to contain function,
and run I<action-if-found>. If the function is not found, run
I<action-if-not-found>.

If linking with library results in unresolved symbols that would be
resolved by linking with additional libraries, give those libraries as
the I<other-libraries> argument: e.g., C<[qw(Xt X11)]>. Otherwise, this
method fails to detect that function is present, because linking the
test program always fails with unresolved symbols.

The result of this test is cached in the ac_cv_search_function variable
as "none required" if function is already available, as C<0> if no
library containing function was found, otherwise as the -llibrary option
that needs to be prepended to LIBS.

=cut

sub search_libs {
  my ( $self, $func, $libs, $action_if_found, $action_if_not_found, @other_libs ) = @_;
  ref($self) or $self = $self->_get_instance();

  ( defined( $libs ) and "ARRAY" eq ref( $libs ) and scalar( @{$libs} ) > 0 )
    or return 0; # XXX would prefer croak
  return 0 unless $func;

  scalar( @other_libs ) == 1 and ref( $other_libs[0] ) eq "ARRAY"
    and @other_libs = @{ $other_libs[0] };

  my $cache_name = $self->_cache_name( "search", $func );
  my $check_sub = sub {

    my $conftest = $self->lang_call( "", $func );

    my @save_libs = @{$self->{extra_libs}};
    my $have_lib = 0;
    foreach my $libstest ( undef, @$libs ) {
      # XXX would local work on array refs? can we omit @save_libs?
      $self->{extra_libs} = [ @save_libs ];
      defined( $libstest ) and unshift( @{$self->{extra_libs}}, $libstest, @other_libs );
      $self->link_if_else( $conftest ) and ( $have_lib = defined( $libstest ) ? $libstest : "none required" ) and last;
    }
    $self->{extra_libs} = [ @save_libs ];
    if( $have_lib ) {
      $have_lib eq "none required" or unshift( @{$self->{extra_libs}}, $have_lib );

      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $have_lib;
  };

  return $self->check_cached( $cache_name, "for library containing $func", $check_sub );
}

#
#
# Auxiliary funcs
#

sub _sanitize {
  # This is hard coded, and maybe a little stupid...
  my $x = shift;
  $x =~ s/ //g;
  $x =~ s/\///g;
  $x =~ s/\\//g;
  return $x;
}

sub _get_instance {
  my $class = shift;
  ref $class and return $class;
  defined( $glob_instance ) and ref( $glob_instance ) and return $glob_instance;
  $glob_instance = $class->new();
  return $glob_instance;
}

sub _get_builder {
  my $self = $_[0]->_get_instance();
  defined( $self->{lang_supported}->{ $self->{lang} } ) or croak( "Unsupported compile language \"" . $self->{lang} . "\"" );

  my $builder = $self->{lang_supported}->{ $self->{lang} }->new( quiet => 1 );

  ## XXX - Temporarily. Will try to send upstream
  if ($self->{lang} eq "C") {
      $builder->{config}{ccflags} =~ s/-arch \S+//g;
      $builder->{config}{lddlflags} =~ s/-arch \S+//g;
      $builder->{config}{ldflags} =~ s/-arch \S+//g;
  }
  return $builder;

}

sub _set_language {
  my $self = shift->_get_instance();
  my ($lang, $impl) = @_;

  defined( $lang ) or croak( "Missing language" );

  defined( $impl ) and defined( $self->{lang_supported}->{$lang} )
    and $impl ne $self->{lang_supported}->{$lang}
    and croak( "Language implementor ($impl) doesn't match exisiting one (" . $self->{lang_supported}->{$lang} . ")" );

  defined( $impl ) and !defined( $self->{lang_supported}->{$lang} )
    and $self->{lang_supported}->{$lang} = $impl;

  defined( $self->{lang_supported}->{$lang} ) or croak( "Unsupported language \"$lang\"" );

  defined( $self->{extra_compile_flags}->{$lang} ) or $self->{extra_compile_flags}->{$lang} = [];

  $self->{lang} = $lang;

  return;
}

sub _fill_defines {
  my ($self, $src, $action_if_true, $action_if_false) = @_;
  ref $self or $self = $self->_get_instance();

  my $conftest = "";
  while( my ($defname, $defcnt) = each( %{ $self->{defines} } ) ) {
    $defcnt->[0] or next;
    defined $defcnt->[1] and $conftest .= "/* " . $defcnt->[1] . " */\n";
    $conftest .= join( " ", "#define", $defname, $defcnt->[0] ) . "\n";
  }
  $conftest .= "/* end of conftest.h */\n";

  return $conftest;
}

#
# default includes taken from autoconf/headers.m4
#

=head2 _default_includes

returns a string containing default includes for program prologue taken
from autoconf/headers.m4:

  #include <stdio.h>
  #ifdef HAVE_SYS_TYPES_H
  # include <sys/types.h>
  #endif
  #ifdef HAVE_SYS_STAT_H
  # include <sys/stat.h>
  #endif
  #ifdef STDC_HEADERS
  # include <stdlib.h>
  # include <stddef.h>
  #else
  # ifdef HAVE_STDLIB_H
  #  include <stdlib.h>
  # endif
  #endif
  #ifdef HAVE_STRING_H
  # if !defined STDC_HEADERS && defined HAVE_MEMORY_H
  #  include <memory.h>
  # endif
  # include <string.h>
  #endif
  #ifdef HAVE_STRINGS_H
  # include <strings.h>
  #endif
  #ifdef HAVE_INTTYPES_H
  # include <inttypes.h>
  #endif
  #ifdef HAVE_STDINT_H
  # include <stdint.h>
  #endif
  #ifdef HAVE_UNISTD_H
  # include <unistd.h>
  #endif

=cut

sub _default_includes {
  my $conftest .= <<"_ACEOF";
#include <stdio.h>
#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif
#ifdef HAVE_SYS_STAT_H
# include <sys/stat.h>
#endif
#ifdef STDC_HEADERS
# include <stdlib.h>
# include <stddef.h>
#else
# ifdef HAVE_STDLIB_H
#  include <stdlib.h>
# endif
#endif
#ifdef HAVE_STRING_H
# if !defined STDC_HEADERS && defined HAVE_MEMORY_H
#  include <memory.h>
# endif
# include <string.h>
#endif
#ifdef HAVE_STRINGS_H
# include <strings.h>
#endif
#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif
#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif
#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif
_ACEOF

  return $conftest;
}

sub _default_main {
  return $_[0]->_build_main("");
}

sub _build_main {
  my $self = shift->_get_instance();
  my $body = shift || "";

  my $conftest .= <<"_ACEOF";
  int
  main ()
  {
    $body;
    return 0;
  }
_ACEOF

  return $conftest;
}

sub _cache_prefix {
  return "ac";
}

sub _cache_name {
  my ($self, @names) = @_;
  my $cache_name = join( "_", $self->_cache_prefix(), "cv", @names );
     $cache_name =~ tr/_A-Za-z0-9/_/c;
  if( $cache_name eq "ac_cv_0_0" ) {
    Test::More::diag( "break here" );
  }
  return $cache_name;
}

sub _get_log_fh {
  my $self = $_[0]->_get_instance();
  unless( defined( $self->{logfh} ) ) {
    open( $self->{logfh}, ">", $self->{logfile} ) or croak "Could not open file $self->{logfile}: $!";
  }

  return $self->{logfh};
}

sub _add2log {
  my ($self, @logentries) = @_;
  ref($self) or $self = $self->_get_instance();
  $self->_get_log_fh();
  foreach my $logentry (@logentries) {
    print {$self->{logfh}} "$logentry\n";
  }

  return;
}

sub _cache_type_name  {
  my ($self, @names) = @_;
  return $self->_cache_name( map { $_ =~ tr/*/p/; $_ } @names );
}

sub _get_extra_compiler_flags {
  my $self = shift->_get_instance();
  my @ppflags = @{$self->{extra_preprocess_flags}};
  my @cflags = @{$self->{extra_compile_flags}->{ $self->{lang} }};
  return join( " ", @ppflags, @cflags );
}

sub _get_extra_linker_flags {
  my $self = shift->_get_instance();
  my @libs = @{$self->{extra_libs}};
  my @ldflags = @{$self->{extra_link_flags}};
  return join( " ", @ldflags, map { "-l$_" } @libs );
}

=head1 AUTHOR

Alberto Simões, C<< <ambs@cpan.org> >>

Jens Rehsack, C<< <rehsack@cpan.org> >>

=head1 NEXT STEPS

Although a lot of work needs to be done, this is the next steps I
intent to take.

  - detect flex/lex
  - detect yacc/bison/byacc
  - detect ranlib (not sure about its importance)

These are the ones I think not too much important, and will be
addressed later, or by request.

  - detect an 'install' command
  - detect a 'ln -s' command -- there should be a module doing
    this kind of task.

=head1 BUGS

A lot. Portability is a pain. B<<Patches welcome!>>.

Please report any bugs or feature requests to
C<bug-extutils-autoconf@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically
be notified of progress on your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

Michael Schwern for kind MacOS X help.

Ken Williams for ExtUtils::CBuilder

=head1 COPYRIGHT & LICENSE

Copyright 2004-2011 by the Authors

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

ExtUtils::CBuilder(3)

=cut

1; # End of Config::AutoConf
