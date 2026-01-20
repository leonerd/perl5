use strict;
use warnings;
use feature 'signatures';

use Test::More;

use XS::APItest;

# Viral value hooks drag HkAUXSV around
{
    my $auxsv;

    my $x;
    sv_hook_add($x, viral => \$auxsv);
    is(Internals::SvREFCNT($auxsv), 2, '$auxsv has refcount 2 after add');

    # copy SV to SV
    {
        my $y = $x;
        ok(sv_hook_exists($y, 'viral'), '$y has viral hook after copy from $x');
        is(HkAUXSV($y, 'viral'), \$auxsv, '$y has auxsv');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after copy');
    }

    # copy SV to AV elem
    {
        my @arr;
        $arr[0] = $x;
        ok(sv_hook_exists($arr[0], 'viral'), '$arr[0] has viral hook after copy from $x');
        is(HkAUXSV($arr[0], 'viral'), \$auxsv, '$arr[0] has auxsv');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after copy');
    }

    # copy SV to HV elem
    {
        my %hash;
        $hash{key} = $x;
        ok(sv_hook_exists($hash{key}, 'viral'), '$hash{key} has viral hook after copy from $x');
        is(HkAUXSV($hash{key}, 'viral'), \$auxsv, '$hash{key} has auxsv');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after copy');
    }

    # call/return
    {
        # pass by $_[0]
        (sub {
            ok(sv_hook_exists($_[0], 'viral'), '$_[0] has viral hook after copy from caller');
        })->($x);

        # pass by shift
        (sub {
            ok(sv_hook_exists(shift, 'viral'), 'shift has viral hook after copy from caller');
        })->($x);

        # pass by signature
        (sub ($y) {
            ok(sv_hook_exists($y, 'viral'), 'signature var has viral hook after copy from caller');
        })->($x);

        ok(sv_hook_exists((sub { return $x })->(), 'viral'),
            'returned value has viral hook');
    }
}

# Viral value hooks are removed when required
{
    my $src;
    sv_hook_add($src, viral => undef);

    {
        my $x = $src;
        undef $x;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after undef');
    }

    {
        my $x = $src;
        $x = undef;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after overwrite with undef');
    }

    {
        my $x = $src;
        $x = 123;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after overwrite with 123');
    }

    {
        my $x = $src;
        my $y = 456;
        $x = $y;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after overwrite with SV');
    }
}

# Now we know that basic call/return works, we can use this to create more
# compact testing functions
#
# We do each test twice in a row to check that old values don't leak from
# e.g. pad temporaries

sub viral_ok ( $code, $name )
{
    foreach my $round (qw( first second )) {
        my $inp;
        sv_hook_add($inp, viral => \"test-val $round");

        my $out = $code->( $inp );
        is_deeply([HkAUXSV_values($out, 'viral')], ["test-val $round"],
            "$name passes viral hook");
    }
}

# array ops
viral_ok(sub ($x) { my @arr; push @arr, $x; $arr[0] }, 'push');
viral_ok(sub ($x) { my @arr; unshift @arr, $x; $arr[0] }, 'unshift');
viral_ok(sub ($x) { my @arr = ( $x ); shift @arr }, 'shift');
viral_ok(sub ($x) { my @arr = ( $x ); pop @arr }, 'pop');
viral_ok(sub ($x) { my @arr; splice @arr, 0, 0, ( $x ); $arr[0] }, 'splice in');
viral_ok(sub ($x) { my @arr = ( $x ); splice @arr, 0, 1 }, 'splice out');

# hash ops
viral_ok(sub ($x) { my %hash = ( key => $x ); ( values %hash )[0] }, 'values');
viral_ok(sub ($x) { my %hash = ( key => $x ); delete $hash{key} }, 'delete');

# other control flow
viral_ok(sub ($x) { my $ret = do { $x; }; $ret }, 'do BLOCK');
viral_ok(sub ($x) { my $ret = eval { $x; }; $ret }, 'eval BLOCK');

done_testing;
