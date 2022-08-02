#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    require Config;
}

use v5.36;
use warnings;
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

# Classes are still regular packages
{
    class Test2 {
        my $ok = "OK";
        sub NotAMethod { return $ok }
    }

    is(Test2::NotAMethod(), "OK", 'Class can contain regular subs');
}

# Classes accept full package names
{
    class Test1::Foo {
        method hello { return "This" }
    }
    is Test1::Foo->new->hello, 'This', 'We can support proper package names';
}

# Classes accept full package names
{
    # this warns about a subroutine name.
    #     Subroutine hello redefined at t/class/class.t line 49.
    # I think it should warn about a method name. This will cause confusion
    # when we can disambiguate between methods and subs (and use both int the
    # same class)
    #
    # No yet sure how to test this. Will think about it.
    class Test2::Foo {
        method hello { return "This" }
        method hello { return "That" }
    }
    is Test2::Foo->new->hello, 'That', 'Multiple methods should take the last method definition';
}
# Classes accepts full package names
{
    eval <<'END';
    class class {
        method hello { return "This" }
    }
END
    # I don't know what the error should be, but we don't get one
    ok $@, 'We should have some error from using class as the package name';

    # The following 'is' test, when uncommented, gives the following weird error message:
    #    Invalid version format (negative version number) at t/class/class.t line 53, near "( class"
    #    syntax error at t/class/class.t line 53, near "( class"

    # is( class->new->hello, 'This', 'We can support proper package names' );
}
done_testing;
