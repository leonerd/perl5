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

# === behaves like == on defined numbers
ok(123 === 123,      '=== on identical values');
ok(0 === 0,          '=== on zero/zero');
ok(not(123 === 456), '=== on different values');

# === treats undef as distinct, equal to itself, with no warnings
{
    my $warnings = 0;
    local $SIG{__WARN__} = sub { $warnings++; };

    ok(undef === undef,  '=== on undef/undef');
    ok(not(undef === 0), '=== on undef/zero');

    is($warnings, 0, 'no warnings were produced by use of undef');
}

# === is chainable
foreach my ( $x, $y, $z )
  ( 123, 123,   123,
    123, 123,   456,
    123, 0,     0,
    123, 0,     undef,
    0,   undef, "" )
{
    no warnings 'uninitialized';

    is($x === $y === $z, ($x === $y) && ($y === $z),
        '=== chains correctly for ' . join("/", map { defined ? qq("$_") : 'undef' } $x, $y, $z ));

    # === chaining with == behaves as expected
    is($x === $y ==  $z, ($x === $y) && ($y ==  $z),
        '=== and == chain correctly for ' . join("/", map { $_ // 'undef' } $x, $y, $z ));
    is($x ==  $y === $z, ($x ==  $y) && ($y === $z),
        '== and === chain correctly for ' . join("/", map { $_ // 'undef' } $x, $y, $z ));
}

# !== is inverted ===
foreach my ( $left, $right )
  ( 123, 123,
    123, 456,
    0, undef,
    undef, undef )
{
    is(not($left !== $right), ($left === $right), '!== is a synonym for not(===)');
}

# === respects 'use integer'
{
    use integer;
    my $x = 123.1;
    ok    ($x === 123, '=== respects use integer');
    not_ok($x !== 123, '!== respects use integer');

    my $nearzero = 0.1;
    ok    ($nearzero === 0,     '=== works under use integer');
    not_ok($nearzero !== 0,     '!== works under use integer');
    not_ok($nearzero === 1,     '=== works under use integer');
    ok    ($nearzero !== 1,     '!== works under use integer');
    not_ok($nearzero === undef, '=== works under use integer');
    ok    ($nearzero !== undef, '!== works under use integer');
}

done_testing();
