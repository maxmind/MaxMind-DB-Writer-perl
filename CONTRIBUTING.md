# CONTRIBUTING

Thank you for considering contributing to this distribution. This file
contains instructions that will help you work with the source code.

Please note that if you have any questions or difficulties, you can reach the
maintainer(s) through the bug queue described later in this document
(preferred), or by emailing the releaser directly. You are not required to
follow any of the steps in this document to submit a patch or bug report;
these are recommendations, intended to help you (and help us help you faster).


The distribution is managed with
[Dist::Zilla](https://metacpan.org/release/Dist-Zilla).

However, you can still compile and test the code with the `Makefile.PL` or
`Build.PL` in the repository:

    perl Makefile.PL
    make
    make test

or

    perl Build.PL
    ./Build
    ./Build test

As well as:

    $ prove -bvr t

or

    $ perl -Mblib t/some_test_file.t

You may need to satisfy some dependencies. The easiest way to satisfy
dependencies is to install the last release. This is available at
https://metacpan.org/release/MaxMind-DB-Writer

If you use cpanminus, you can do it without downloading the tarball first:

    $ cpanm --reinstall --installdeps --with-recommends MaxMind::DB::Writer

Dist::Zilla is a very powerful authoring tool, but requires a number of
author-specific plugins. If you would like to use it for contributing, install
it from CPAN, then run one of the following commands, depending on your CPAN
client:

    $ cpan `dzil authordeps --missing`

or

    $ dzil authordeps --missing | cpanm

There may also be additional requirements not needed by the dzil build which
are needed for tests or other development:

    $ cpan `dzil listdeps --author --missing`

or

    $ dzil listdeps --author --missing | cpanm

Or, you can use the 'dzil stale' command to install all requirements at once:

    $ cpan Dist::Zilla::App::Command::stale
    $ cpan `dzil stale --all`

or

    $ cpanm Dist::Zilla::App::Command::stale
    $ dzil stale --all | cpanm

You can also do this via cpanm directly:

    $ cpanm --reinstall --installdeps --with-develop --with-recommends MaxMind::DB::Writer

Once installed, here are some dzil commands you might try:

    $ dzil build
    $ dzil test
    $ dzil test --release
    $ dzil xtest
    $ dzil listdeps --json
    $ dzil build --notgz

You can learn more about Dist::Zilla at http://dzil.org/.

The code for this distribution is [hosted at GitHub](https://github.com/maxmind/MaxMind-DB-Writer-perl).

You can submit code changes by forking the repository, pushing your code
changes to your clone, and then submitting a pull request. Detailed
instructions for doing that is available here:

https://help.github.com/articles/creating-a-pull-request

If you have found a bug, but do not have an accompanying patch to fix it, you
can submit an issue report [via the web](https://github.com/maxmind/MaxMind-DB-Writer-perl/issues)
.
This is a good place to send your questions about the usage of this distribution.


## Tidyall

This distribution uses
[Code::TidyAll](https://metacpan.org/release/Code-TidyAll) to enforce a
uniform coding style. This is tested as part of the author testing suite. You
can install and run tidyall by running the following commands:

    $ cpanm Code::TidyAll
    $ tidyall -a

Please run this before committing your changes and address any issues it
brings up.

## Contributor Names

If you send a patch or pull request, your name and email address will be
included in the documentation as a contributor (using the attribution on the
commit or patch), unless you specifically request for it not to be. If you
wish to be listed under a different name or address, you should submit a pull
request to the .mailmap file to contain the correct mapping.
[Check here](https://github.com/git/git/blob/master/Documentation/mailmap.txt)
for more information on git's .mailmap files.

This file was generated via Dist::Zilla::Plugin::GenerateFile::FromShareDir 0.015 from a
template file originating in Dist-Zilla-PluginBundle-MAXMIND-0.84.
