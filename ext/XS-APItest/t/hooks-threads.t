use strict;
use warnings;
use Config;

BEGIN {
    if( !$Config{usethreads} ) {
        require Test::More;
        Test::More::plan( skip_all => "No threads" );
    }
}

use XS::APItest;

# We must 'use threads' before 'use Test::More' so the test count sync works
use threads;
use Test::More;

# HkAUXSV cloning into thread
{
    my $sv;
    sv_hook_add($sv, empty => \(my $tmp = "orig-data"));

    threads->create(sub {
        my $auxsvref = HkAUXSV($sv, 'empty');
        is($$auxsvref, "orig-data", 'sv_find_hook sees auxsv inside thread');
        $$auxsvref = "new-data";
        is($$auxsvref, "new-data", 'can modify data inside thread');
    })->join;

    my $auxsvref = HkAUXSV($sv, 'empty');
    is($$auxsvref, "orig-data", 'sv_find_hook sees original auxsv in main');
}

# HkPTR cloning into thread
{
    my $sv;
    sv_hook_add($sv, empty => undef);
    hk_ptr_store($sv, 'empty', "ABCDE");

    threads->create(sub {
        is(HkPTR($sv, 'empty'), "ABCDE", 'sv_find_hook sees HkPTR cloned inside thread');

        HkPTR_write($sv, 'empty', "ZYXWV");
        is(HkPTR($sv, 'empty'), "ZYXWV", 'HkPTR can be updated inside thread');
    })->join;

    is(HkPTR($sv, 'empty'), "ABCDE", 'Original HkPTR is retained');
}

# HkKEYIV cloning into thread
{
    my $sv;
    sv_hook_add($sv, with_keyiv => undef);
    HkKEYIV_set($sv, with_keyiv => 12345);

    threads->create(sub {
        is(HkKEYIV($sv, 'with_keyiv'), 12345, 'HkKEYIV is set inside thread');

        HkKEYIV_set($sv, with_keyiv => 54321);
        is(HkKEYIV($sv, 'with_keyiv'), 54321, 'HkKEYIV can be updated inside thread');
    })->join;

    is(HkKEYIV($sv, 'with_keyiv'), 12345, 'Original HkKEYIV is retained');
}

# HkKEYSV cloning into thread
{
    my $sv;
    sv_hook_add($sv, with_keysv => undef);
    HkKEYSV_set($sv, with_keysv => "XYZ");

    threads->create(sub {
        is(HkKEYSV($sv, 'with_keysv'), "XYZ", 'HkKEYSV is set inside thread');

        HkKEYSV_set($sv, with_keysv => "ZYX");
        is(HkKEYSV($sv, 'with_keysv'), "ZYX", 'HkKEYSV can be updated inside thread');
    })->join;

    is(HkKEYSV($sv, 'with_keysv'), "XYZ", 'Original HkKEYSV is retained');
}

# clone hook is invoked
{
    my $sv;
    sv_hook_add($sv, inc_on_clone => \(my $counter = 1));

    threads->create(sub {
        is($counter, 2, '$counter is 2 inside thread');
    })->join;

    is($counter, 1, '$counter remains 1 in main');
}

# userstruct cloning into a thread
{
    my $sv;
    sv_hook_add($sv, userstruct => undef);

    threads->create(sub {
        is_deeply([sv_hook_get_userstruct($sv)], [123, 456],
            'Hook user struct gets copied on thread clone');
    })->join;
}

done_testing();
