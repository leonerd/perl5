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
    class Test3::Foo {
        method hello { return "This" }
    }
    is(Test3::Foo->new->hello, "This", 'Class supports fully-qualified package names');
}

# Class {BLOCK} syntax parses like package
{
    my $result = "";
    eval q{
        $result .= "a(" . __PACKAGE__ . "/" . eval("__PACKAGE__") . ")\n";
        class Test4 1.23 {
            $result .= "b(" . __PACKAGE__ . "/" . eval("__PACKAGE__") . ")\n";
        }
        $result .= "c(" . __PACKAGE__ . "/" . eval("__PACKAGE__") . ")\n";
    } or die $@;
    is($result, "a(main/main)\nb(Test4/Test4)\nc(main/main)\n",
        'class sets __PACKAGE__ correctly');
    is($Test4::VERSION, 1.23, 'class NAME VERSION { BLOCK } sets $VERSION');
}

# Unit class syntax parses like package
{
    my $result = "";
    eval q{
        $result .= "a(" . __PACKAGE__ . "/" . eval("__PACKAGE__") . ")\n";
        class Test5 4.56;
        $result .= "b(" . __PACKAGE__ . "/" . eval("__PACKAGE__") . ")\n";
        package main;
        $result .= "c(" . __PACKAGE__ . "/" . eval("__PACKAGE__") . ")\n";
    } or die $@;
    is($result, "a(main/main)\nb(Test5/Test5)\nc(main/main)\n",
        'class sets __PACKAGE__ correctly');
    is($Test5::VERSION, 4.56, 'class NAME VERSION; sets $VERSION');
}

done_testing;
