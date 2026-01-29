use strict;
use warnings;
use Test::More;

use XS::APItest;

# HkPRIV storage
{
    my $sv;
    sv_hook_add($sv, empty => undef, 1234);
    is(HkPRIV($sv, 'empty'), 1234, 'sv_hook_find retrieves HkPRIV value');
}

# HkAUXSV refcounting
{
    my $auxsv;
    {
        my $sv;
        sv_hook_add($sv, empty => \$auxsv);

        ok(sv_hook_exists($sv, 'empty'), 'sv_hook_exists finds empty hook');

        is(Internals::SvREFCNT($auxsv), 2, '$auxsv has refcount 2 before drop');
    }
    is(Internals::SvREFCNT($auxsv), 1, '$auxsv has refcount 1 after drop');

    # HkAUXSV_set can replace it
    {
        my $sv;
        sv_hook_add($sv, empty => \$auxsv);

        is(Internals::SvREFCNT($auxsv), 2, '$auxsv has refcount 2 before HkAUXSV_set');

        HkAUXSV_set($sv, empty => my $arr = []);

        is(HkAUXSV($sv, 'empty'), $arr, 'HkAUXSV_set has replaced aux SV');
        is(Internals::SvREFCNT($auxsv), 1, '$auxsv has refcount 1 after HkAUXSV_set');
        is(Internals::SvREFCNT(@$arr), 2, '@$arr has refcount 2 after HkAUXSV_set');
    }
}

# HkAUXSV with WEAK_AUXSV
{
    my $auxsv;
    {
        my $sv;
        sv_hook_add($sv, weak => \$auxsv);

        ok(sv_hook_exists($sv, 'weak'), 'sv_hook_exists finds weak hook');

        is(Internals::SvREFCNT($auxsv), 1, '$auxsv has refcount 2 before drop');
    }
    is(Internals::SvREFCNT($auxsv), 1, '$auxsv has refcount 1 after drop');

    # HkAUXSV_set can replace it
    {
        my $sv;
        sv_hook_add($sv, weak => \$auxsv);

        is(Internals::SvREFCNT($auxsv), 1, '$auxsv has refcount 1 before HkAUXSV_set');

        HkAUXSV_set($sv, weak => my $arr = []);

        is(HkAUXSV($sv, 'weak'), $arr, 'HkAUXSV_set has replaced aux SV');
        is(Internals::SvREFCNT($auxsv), 1, '$auxsv has refcount 1 after HkAUXSV_set');
        is(Internals::SvREFCNT(@$arr), 1, '@$arr has refcount 1 after HkAUXSV_set');
    }
}

# HkPTR can store a byte buffer
{
    my $sv;
    sv_hook_add($sv, empty => undef);
    hk_ptr_store($sv, 'empty', "ABCDE");

    is(HkPTR($sv, 'empty'), "ABCDE", 'HkPTR can store a byte buffer');
}

# HkPTRLEN is usable on its own
{
    my $sv;
    sv_hook_add($sv, empty => undef);

    HkPTRLEN_set($sv, 'empty', 123456);
    is(HkPTRLEN($sv, 'empty'), 123456, 'HkPTRLEN is usable on its own');
}

# HkKEYIV
{
    my $sv;
    sv_hook_add($sv, with_keyiv => undef);

    is(HkKEYIV($sv, 'with_keyiv'), 0, 'HkKEYIV is zero initially');

    HkKEYIV_set($sv, with_keyiv => 12345);
    is(HkKEYIV($sv, 'with_keyiv'), 12345, 'HkKEYIV can be set to a value');
}

# HkKEYSV
{
    my $sv;
    sv_hook_add($sv, with_keysv => undef);

    is(HkKEYSV($sv, 'with_keysv'), undef, 'HkKEYSV is zero initially');

    HkKEYSV_set($sv, with_keysv => "XYZ");
    is(HkKEYSV($sv, 'with_keysv'), "XYZ", 'HkKEYSV can be set to a value');
}

# sv_hook_find
{
    my $sv;
    sv_hook_add($sv, empty => \"the auxsv data");
    my $auxsvref = HkAUXSV($sv, 'empty');
    is($$auxsvref, "the auxsv data", 'sv_hook_find can find Hook structure');
    is(HkAUXSV_value($sv, 'empty'), "the auxsv data", 'HkAUXSV_value works');
    ok(!defined HkAUXSV($sv, 'inc_on_free'), 'sv_hook_find does not see wrong hook');
}

# Can add the same hook multiple times
{
    my $sv;
    sv_hook_add($sv, empty => \"data 1");
    sv_hook_add($sv, empty => \"data 2");
    # We don't guarantee what the order will be
    is_deeply([sort +HkAUXSV_values($sv, 'empty')], ["data 1", "data 2"],
        "HkAUXSV_values can see multiple auxsv");
}

# free hook is invoked
{
    my $counter;
    {
        my $sv = 123;
        sv_hook_add($sv, inc_on_free => \$counter);
    }
    is $counter, 1, '$counter is now 1 after SV free';
}

# userstruct can store more data
{
    my $sv;
    sv_hook_add($sv, userstruct => undef);

    is_deeply([sv_hook_get_userstruct($sv)], [123, 456],
        'Hook gets initialised with userstruct data');

    sv_hook_set_userstruct($sv, 987, 654);
    is_deeply([sv_hook_get_userstruct($sv)], [987, 654],
        'Userstruct data can be modified');
}

# Hook can be removed
{
    my $counter;
    my $sv = 123;
    sv_hook_add($sv, inc_on_free => \$counter);
    sv_hook_remove($sv, 'inc_on_free');
    is($counter, 1, '$counter is now 1 after sv_hook_remove');
}

# Removed hooks don't disturb others
{
    my $counterA;
    my $counterB;
    {
        my $sv;
        sv_hook_add($sv, inc_on_free => \$counterA);
        sv_hook_add($sv, empty => \undef);
        sv_hook_add($sv, inc_on_free => \$counterB);

        sv_hook_remove($sv, 'empty');
    }
    is($counterA, 1, 'first inc_on_free hook invoked after empty hook removed');
    is($counterB, 1, 'second inc_on_free hook invoked after empty hook removed');
}

# Non-container hooks do not persist through `local`
{
    my $auxsv;
    # we can't local'ise a lexical var
    my @var = (undef);
    sv_hook_add($var[0], empty => \$auxsv);

    {
        local $var[0];
        is(HkAUXSV($var[0], 'empty'), undef, 'sv_hook_find sees nothing while localised');
    }

    is(HkAUXSV($var[0], 'empty'), \$auxsv, 'sv_hook_find after SV restored');
}

# Container hooks keep HkAUXSV across `local`
{
    my $auxsv;
    # we can't local'ise a lexical var
    my @var = (undef);
    sv_hook_add($var[0], container_empty => \$auxsv);

    {
        local $var[0];
        is(HkAUXSV($var[0], 'container_empty'), \$auxsv, 'sv_hook_find sees auxsv localised');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after local');
    }

    is(HkAUXSV($var[0], 'container_empty'), \$auxsv, 'sv_hook_find after SV restored');
}

# Container hooks keep HkPTR across `local`
{
    # we can't local'ise a lexical var
    my @var = (undef);
    sv_hook_add($var[0], container_empty => undef);
    hk_ptr_store($var[0], 'container_empty' => "ABCDE");

    {
        local $var[0];
        is(HkPTR($var[0], 'container_empty'), "ABCDE", 'HkPTR copied on local');

        HkPTR_write($var[0], 'container_empty', "ZYXWV");
        is(HkPTR($var[0], 'container_empty'), "ZYXWV", 'HkPTR can be updated');
    }

    is(HkPTR($var[0], 'container_empty'), "ABCDE", 'Original HkPTR is retained');
}

# Container hooks keep HkPTRLEN across `local`
{
    # we can't local'ise a lexical var
    my @var = (undef);
    sv_hook_add($var[0], container_empty => undef);
    HkPTRLEN_set($var[0], 'container_empty', 7654);

    {
        local $var[0];
        is(HkPTRLEN($var[0], 'container_empty'), 7654, 'HkPTRLEN copied on local');
    }
}

# Container hooks keep HkKEYIV across `local`
{
    # we can't local'ise a lexical var
    my @var = (undef);
    sv_hook_add($var[0], with_keyiv => undef);
    HkKEYIV_set($var[0], 'with_keyiv', 7654);

    {
        local $var[0];
        is(HkKEYIV($var[0], 'with_keyiv'), 7654, 'HkKEYIV copied on local');
    }
}

# Container hooks keep HkKEYSV across `local`
{
    # we can't local'ise a lexical var
    my @var = (undef);
    sv_hook_add($var[0], with_keysv => undef);
    HkKEYSV_set($var[0], 'with_keysv', "EFGH");

    {
        local $var[0];
        is(HkKEYSV($var[0], 'with_keysv'), "EFGH", 'HkKEYSV copied on local');
    }
}

# Scalar Variable hooks with 'post_set' function
{
    my $counter;
    my $sv = 123;
    sv_hook_add($sv, inc_after_set => \$counter);
    is $counter, undef, '$counter before SV modify';

    $sv = 456;
    is $counter, 1, '$counter after SV modify';

    undef $sv;
    is $counter, 2, '$counter after SV undef';

    my $counter2;
    sv_hook_add($sv, inc_after_set => \$counter2);
    $sv = 789;

    is $counter,  3, '$counter after SV modify';
    is $counter2, 1, '$counter2 after SV modify';
}

# Scalar Variable hooks with 'pre_get' function
{
    my $shadow = 456;
    my $sv = 123;
    sv_hook_add($sv, grab_before_get => \$shadow);
    is $sv+0, 456, '$sv appears as a copy of $shadow';

    # length is weird in magic
    $shadow = "x" x 100;
    is length($sv), 100, 'length($sv) from shadow';
}

# Scalar Variable hooks persist through `local`
{
    my $counter;
    # we can't local'ise a lexical var
    my @var = ( "a" );
    sv_hook_add($var[0], inc_after_set => \$counter);
    {
        local $var[0] = "b";
        # local + assign has bumped the counter twice
        is $counter, 2, '$counter after SV localised';

        $var[0] = "c";
        is $counter, 3, '$counter after SV modify when localised';
    }

    is $counter, 4, '$counter after SV restored';
}

# Variable hook can be removed while it is running
{
    my $counter;
    my $sv;
    sv_hook_add($sv, inc_after_set => \$counter, 1);

    $sv = 123;
    is $counter, 1, '$counter after SV modify with dispel';

    $sv = 456;
    is $counter, 1, '$counter after SV modify unchanged after dispel';
}

# Array Variable hooks with 'clear' function
{
    my $counter;
    my @arr;
    sv_hook_add(@arr, inc_after_clear_arr => \$counter);

    undef @arr;
    is $counter, 1, '$counter after AV clear with undef';
}

# Hash Variable hooks with 'clear' function
{
    my $counter;
    my %hash;
    sv_hook_add(%hash, inc_after_clear_hash => \$counter);

    undef %hash;
    is $counter, 1, '$counter after HV clear with undef';
}

done_testing;
