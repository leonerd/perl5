#!./perl

use strict;
use warnings;

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

# So many tests are easier to write as not_ok(FOO) rather than extra parens
sub not_ok
{
    my ($not_pass, $name, @mess) = @_;
    ::_ok(!$not_pass, ::_where(), $name, @mess);
}

# equ behaves like eq on defined strings
ok    ("abc" equ "abc", 'equ on identical values');
ok    ("" equ "",       'equ on empty/empty');
not_ok("abc" equ "def", 'equ on different values');

# equ treats undef as distinct, equal to itself, with no warnings
{
    my $warnings = 0;
    local $SIG{__WARN__} = sub { $warnings++; };

    ok    (undef equ undef, 'equ on undef/undef');
    not_ok(undef equ "",    'equ on undef/empty');

    is($warnings, 0, 'no warnings were produced by use of undef');
}

# equ is chainable
foreach my ( $x, $y, $z )
  ( "abc", "abc", "abc",
    "abc", "abc", "def",
    "abc", "",    "",
    "abc", "",    undef,
    "",    undef, "" )
{
    no warnings 'uninitialized';

    is($x equ $y equ $z, ($x equ $y) && ($y equ $z),
        'equ chains correctly for ' . join("/", map { defined ? qq("$_") : 'undef' } $x, $y, $z ));

    # equ chaining with eq behaves as expected
    is($x equ $y eq  $z, ($x equ $y) && ($y eq  $z),
        'equ and eq chain correctly for ' . join("/", map { defined ? qq("$_") : 'undef' } $x, $y, $z ));
    is($x eq  $y equ $z, ($x eq  $y) && ($y equ $z),
        'eq and equ chain correctly for ' . join("/", map { defined ? qq("$_") : 'undef' } $x, $y, $z ));
}

# equ still compares references like strings
{
    my $arr = [];
    my $arrstr = "$arr";
    ok($arr equ $arrstr, 'equ stringifies defined references');
}

# neu is inverted equ
foreach my ( $left, $right )
  ( "abc", "abc",
    "abc", "def",
    "", undef,
    undef, undef )
{
    is(not($left neu $right), ($left equ $right), 'neu is a synonym for not(equ)');
}

done_testing();
