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

# class NAME { BLOCK }
$main::result = "";
eval q{
    $main::result .= "a(".__PACKAGE__."/".eval("__PACKAGE__").")\n";
    class Test1 1.23 {
        $main::result .= "b(".__PACKAGE__."/".eval("__PACKAGE__").")\n";
    }
    $main::result .= "c(".__PACKAGE__."/".eval("__PACKAGE__").")\n";
    1;
} or die $@;
is($main::result,
    "a(main/main)\n" .
    "b(Test1/Test1)\n" .
    "c(main/main)\n");
is($Test1::VERSION, 1.23, 'class NAME VERSION { BLOCK } sets $VERSION');

# class NAME; ...
$main::result = "";
eval q{
    $main::result .= "a(".__PACKAGE__."/".eval("__PACKAGE__").")\n";
    class Test2 4.56;
    $main::result .= "b(".__PACKAGE__."/".eval("__PACKAGE__").")\n";
    package main;
    $main::result .= "c(".__PACKAGE__."/".eval("__PACKAGE__").")\n";
    1;
} or die $@;
is($main::result,
    "a(main/main)\n" .
    "b(Test2/Test2)\n" .
    "c(main/main)\n");
is($Test2::VERSION, 4.56, 'class NAME VERSION; sets $VERSION');

done_testing;
