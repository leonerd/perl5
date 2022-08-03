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

# methods have signatures; signatures do not capture $self
{
    class Test2 {
        method retfirst ( $x = 123 ) { return $x; }
    }

    my $obj = Test2->new;
    is($obj->retfirst,      123, 'method signature params work');
    is($obj->retfirst(456), 456, 'method signature params skip $self');
}

# methods can still capture regular package lexicals
{
    class Test3 {
        my $count;
        method inc { return $count++ }
    }

    my $obj1 = Test3->new;
    $obj1->inc;

    is($obj1->inc, 1, '$obj1->inc sees 1');

    my $obj2 = Test3->new;
    is($obj2->inc, 2, '$obj2->inc sees 2');
}

# $self is shifted from @_
{
    class Test4 {
        method args { return @_ }
    }

    my $obj = Test4->new;
    ok(eq_array([$obj->args("a", "b")], ["a", "b"]), '$self is shifted from @_');
}

# anon methods
{
    class Test5 {
        method anonmeth {
            return method {
                return "Result";
            }
        }
    }

    my $obj = Test5->new;
    my $mref = $obj->anonmeth;

    is($obj->$mref, "Result", 'anon method can be invoked');
}

{
    class Test6 {
        field $x;
        ADJUST { $x = 0 }
        method inc_x { return ++$x }
        method get_x { $x }
    }

    my $obj = Test6->new;
    is( $obj->get_x, 0, 'Value of $x set by ADJUST' );

    is $obj->inc_x, 1, 'We can increment our value of $x';
    is $obj->inc_x, 2, '... and its value should persist between calls';
    is $obj->get_x, 2, '... no matter what method we access it from';
}

{
    class Delegate {
        method doit { return "tiod" }
    }

    class Test7 {
        field $delegate;

        ADJUST { $delegate = Delegate->new }
        method class { $delegate }
    }
    is Test7->new->class->doit, "tiod", "class can be used as a method name without difficulty (but should it be?)";
}

done_testing;
