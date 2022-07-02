#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    require Config;
}

use v5.36;
use feature 'class';
no warnings 'experimental::class';

{
    class Test1 {
        method hello { return "hello, world"; }
    }

    my $obj = Test1->new;
    isa_ok($obj, "Test1", '$obj');

    is($obj->hello, "hello, world", '$obj->hello');
}

done_testing;
