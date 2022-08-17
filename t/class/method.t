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

# $self in method
{
    class Test1 {
        method retself { return $self }
    }

    my $obj = Test1->new;
    is($obj->retself, $obj, '$self inside method');
}

done_testing;
