use strict;
use warnings;
use utf8;
use autodie;

use lib 't/lib';

use Test::Requires {
    JSON                  => 0,
    'MaxMind::DB::Reader' => 0.040000,
};

use File::Temp qw( tempdir );
use MaxMind::DB::Writer::Tree;
use Net::Works::Network;
use Test::More;
use Test::Warnings qw( :all );

########################################################################
# the purpose of this test is to check the merging arguments are being
# set correctly and act correctly both on an original tree and a
# thawed tree.  This test doesn't fully check either freezing or thawing
# or merging behavior - that's handled by other tests
########################################################################

# this is the IP range we'll be testing and an IP within it
my $NETWORK = Net::Works::Network->new_from_string( string => '::0/1' );
my $IP_ADDRESS = '::123.123.123.123';

sub check_tree {
    my $name                   = shift;
    my $extra_constructor_args = shift;
    my $extra_thaw_args        = shift;
    my $callback               = shift;

    subtest(
        $name,
        sub {
            # we don't use TryTiny here because we're not otherwise depending on it
            return if eval {

                my $tree1 = MaxMind::DB::Writer::Tree->new(
                    ip_version            => 6,
                    record_size           => 24,
                    database_type         => 'Test',
                    languages             => ['en'],
                    description           => { en => 'Test tree' },
                    map_key_type_callback => sub { 'uint32' },
                    @{$extra_constructor_args},
                );

                $tree1->insert_network( $NETWORK, { value => 42 } );

                my $dir = tempdir( CLEANUP => 1 );
                my $file = "$dir/frozen-tree";
                $tree1->freeze_tree($file);

                my $tree2 = MaxMind::DB::Writer::Tree->new_from_frozen_tree(
                    filename              => $file,
                    map_key_type_callback => $tree1->map_key_type_callback(),
                    @{$extra_thaw_args},
                );

                # attempt to stick a second value for the same IP range in both the
                # original and the restored thawed trees, to see what happens with
                # merging now
                $_->insert_network( $NETWORK, { leet => 1337 } )
                    for ( $tree1, $tree2 );

                my ( $record1, $record2 )
                    = map { $_->lookup_ip_address($IP_ADDRESS) }
                    ( $tree1, $tree2 );

                $callback->(
                    original_tree   => $tree1,
                    thawed_tree     => $tree2,
                    original_record => $record1,
                    thawed_record   => $record2,
                );

                1;
            };

            # threw an exception, turn into failing test
            my $err = $@;
            ok( 0, 'Run without exceptions' );
            diag($err);
        }
    );
}

########################################################################
# no merging
########################################################################

check_tree(
    'check defaults work',
    [],
    [],
    sub {
        my %args = @_;

        like(
            warning {
                ok(
                    !$args{thawed_tree}->merge_record_collisions,
                    'thawed merge_record_collisons'
                    )
            },
            qr/merge_record_collisions is deprecated/,
            'received deprecation message'
        );

        is(
            $args{thawed_tree}->merge_strategy, 'none',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                leet => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'check no merging explictly',
    [ merge_strategy => 'none' ],
    [],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'none',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                leet => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'check no merging and none explictly',
    [ merge_strategy => 'none' ],
    [],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'none',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                leet => 1337,
            },
            'check thawed record'
        );
    }
);

########################################################################
# explictly merging in both cases
########################################################################

check_tree(
    'set mrc in constructor, toplevel in thaw',
    [ merge_strategy => 'toplevel' ],
    [ merge_strategy => 'toplevel' ],
    sub {
        my %args = @_;

        like(
            warning {
                ok(
                    $args{thawed_tree}->merge_record_collisions,
                    'thawed merge_record_collisons'
                    )
            },
            qr/merge_record_collisions is deprecated/,
            'received deprecation message'
        );

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set toplevel in constructor',
    [ merge_strategy => 'toplevel' ],
    [ merge_strategy => 'toplevel' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set recurse in constructor',
    [ merge_strategy => 'recurse' ],
    [ merge_strategy => 'recurse' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'recurse',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

########################################################################
# set just in constructore
########################################################################

check_tree(
    'set mrc only in constructor',
    [ merge_strategy => 'toplevel' ],
    [],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set toplevel only in constructor',
    [ merge_strategy => 'toplevel' ],
    [],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set recurse only in constructor',
    [ merge_strategy => 'recurse' ],
    [],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'recurse',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

########################################################################
# set differing options in thaw
########################################################################

check_tree(
    'set toplevel only in thaw',
    [],
    [ merge_strategy => 'toplevel' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set mrc off in constructor, toplevel in thaw',
    [ merge_strategy => 'none' ],
    [ merge_strategy => 'toplevel' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set none in constructor, toplevel only in thaw',
    [ merge_strategy => 'none' ],
    [ merge_strategy => 'toplevel' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'toplevel',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set recurse only in thaw',
    [],
    [ merge_strategy => 'recurse' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'recurse',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

check_tree(
    'set mrc off in constructor, recurse in thaw',
    [ merge_strategy => 'none' ],
    [ merge_strategy => 'recurse' ],
    sub {
        my %args = @_;

        is(
            $args{thawed_tree}->merge_strategy, 'recurse',
            'thawed merge_strategy'
        );
        is_deeply(
            $args{original_record},
            {
                leet => 1337,
            },
            'check original record'
        );
        is_deeply(
            $args{thawed_record},
            {
                value => 42,
                leet  => 1337,
            },
            'check thawed record'
        );
    }
);

done_testing();
