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
        field $x;
        ADJUST { $x = delete (shift->{x}) }
        method x { return $x; }
    }

    my $obj = Test1->new(x => 123);
    is($obj->x, 123, 'Value of $x set by ADJUST');
}

done_testing;
