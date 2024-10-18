#!perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use v5.40;

# a TEMPORARY unit test file for ensuring the 'faster_signatures' feature
# works properly.

sub fails_ok ( $code, $failure_pattern, $title )
{
    eval { $code->(); 1 } and
        return ok( 0, "$title fails" );
    my $e = $@;
    ok( 1, "$title fails" );
    like( $e, $failure_pattern, "$title exception" );
}

use feature 'faster_signatures';

# zero params
sub p0 () { return "P0" }
is( p0(), "P0", 'p0 OK' );
fails_ok( sub { p0("a1") }, qr/^Too many arguments for subroutine 'main::p0' \(got 1; expected 0\) at /,
    'p0 on one argument' );

# one param
sub p1 ( $x ) { return "P1-$x"; }
is( p1("a1"), "P1-a1", 'p1 OK' );
fails_ok( sub { p1() }, qr/^Too few arguments for subroutine 'main::p1' \(got 0; expected 1\) at /,
    'p1 on zero arguments' );
fails_ok( sub { p1("a1","a2") }, qr/^Too many arguments for subroutine 'main::p1' \(got 2; expected 1\) at /,
    'p1 on two arguments' );

# two params
sub p2 ( $x, $y ) { return "P2-$x-$y"; }
is( p2("a1", "a2"), "P2-a1-a2", 'p2 OK' );
fails_ok( sub { p2("a1") }, qr/^Too few arguments for subroutine 'main::p2' \(got 1; expected 2\) at /,
    'p2 on one arguments' );
fails_ok( sub { p2("a1","a2","a3") }, qr/^Too many arguments for subroutine 'main::p2' \(got 3; expected 2\) at /,
    'p2 on three arguments' );

# with slurpy array
sub p1sa ( $x, @rest ) {
    return "P1SA-$x+" . join( '+', @rest );
}
is( p1sa("a1", qw( a b c )), "P1SA-a1+a+b+c", 'p1sa OK' );
fails_ok( sub { p1sa() }, qr/^Too few arguments for subroutine 'main::p1sa' \(got 0; expected at least 1\) at /,
    'p1sa on zero arguments' );

# with slurpy hash
sub p1sh ( $x, %rest ) {
    return "P1SH-$x+" . join( '+', map { "$_=$rest{$_}" } sort keys %rest );
}
is( p1sh("a1", a => "A", b => "B"), "P1SH-a1+a=A+b=B", 'p1ha OK' );
fails_ok( sub { p1sh() }, qr/^Too few arguments for subroutine 'main::p1sh' \(got 0; expected at least 1\) at /,
    'p1sh on zero arguments' );

done_testing;
