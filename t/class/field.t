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

# We can't test fields in isolation without having at least one method to
# use them from. We'll try to keep most of the heavy testing of method
# abilities to t/class/method.t

# field in method
{
    class Test1 {
        field $f;
        method incr { return ++$f; }
    }

    my $obj = Test1->new;
    $obj->incr;
    is($obj->incr, 2, 'Field $f incremented twice');

    my $obj2 = Test1->new;
    is($obj2->incr, 1, 'Fields are distinct between instances');
}

# fields are distinct
{
    class Test2 {
        field $x;
        field $y;

        method setpos { $x = $_[0]; $y = $_[1] }
        method x      { return $x; }
        method y      { return $y; }
    }

    my $obj = Test2->new;
    $obj->setpos(10, 20);
    is($obj->x, 10, '$pos->x');
    is($obj->y, 20, '$pos->y');
}

# fields of all variable types
{
    class Test3 {
        field $s;
        field @a;
        field %h;

        method setup {
            $s = "scalar";
            @a = ( "array" );
            %h = ( key => "hash" );
            return $self; # test chaining
        }
        method test {
            ::is($s,      "scalar", 'scalar storage');
            ::is($a[0],   "array",  'array storage');
            ::is($h{key}, "hash",   'hash storage');
        }
    }

    Test3->new->setup->test;
}

done_testing;
