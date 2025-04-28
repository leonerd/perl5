use strict;
use warnings;
use feature 'signatures';

use Test::More;

use XS::APItest;

# Viral value hooks drag HkAUXSV around
{
    my $auxsv;

    my $x;
    sv_hook_add($x, viral => \$auxsv);
    is(Internals::SvREFCNT($auxsv), 2, '$auxsv has refcount 2 after add');

    # copy SV to SV
    {
        my $y = $x;
        ok(sv_hook_exists($y, 'viral'), '$y has viral hook after copy from $x');
        is(HkAUXSV($y, 'viral'), \$auxsv, '$y has auxsv');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after copy');
    }

    # copy SV to AV elem
    {
        my @arr;
        $arr[0] = $x;
        ok(sv_hook_exists($arr[0], 'viral'), '$arr[0] has viral hook after copy from $x');
        is(HkAUXSV($arr[0], 'viral'), \$auxsv, '$arr[0] has auxsv');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after copy');
    }

    # copy SV to HV elem
    {
        my %hash;
        $hash{key} = $x;
        ok(sv_hook_exists($hash{key}, 'viral'), '$hash{key} has viral hook after copy from $x');
        is(HkAUXSV($hash{key}, 'viral'), \$auxsv, '$hash{key} has auxsv');
        is(Internals::SvREFCNT($auxsv), 3, '$auxsv has refcount 3 after copy');
    }

    # call/return
    {
        # pass by $_[0]
        (sub {
            ok(sv_hook_exists($_[0], 'viral'), '$_[0] has viral hook after copy from caller');
        })->($x);

        # pass by shift
        (sub {
            ok(sv_hook_exists(shift, 'viral'), 'shift has viral hook after copy from caller');
        })->($x);

        # pass by signature
        (sub ($y) {
            ok(sv_hook_exists($y, 'viral'), 'signature var has viral hook after copy from caller');
        })->($x);

        ok(sv_hook_exists((sub { return $x })->(), 'viral'),
            'returned value has viral hook');
    }
}

# Viral value hooks are removed when required
{
    my $src;
    sv_hook_add($src, viral => undef);

    {
        my $x = $src;
        undef $x;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after undef');
    }

    {
        my $x = $src;
        $x = undef;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after overwrite with undef');
    }

    {
        my $x = $src;
        $x = 123;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after overwrite with 123');
    }

    {
        my $x = $src;
        my $y = 456;
        $x = $y;
        ok(!sv_hook_exists($x, 'viral'), '$x no longer has viral hook after overwrite with SV');
    }
}

# Now we know that basic call/return works, we can use this to create more
# compact testing functions
#
# We do each test twice in a row to check that old values don't leak from
# e.g. pad temporaries

sub viral_ok ( $code, $name )
{
    foreach my $round (qw( first second )) {
        my $inp = "inp for $name";
        sv_hook_add($inp, viral => \"test-val $round");

        my $out = $code->( $inp );
        is_deeply([HkAUXSV_values($out, 'viral')], ["test-val $round"],
            "$name passes viral hook");
    }
}

# array ops
viral_ok(sub ($x) { my @arr; push @arr, $x; $arr[0] }, 'push');
viral_ok(sub ($x) { my @arr; unshift @arr, $x; $arr[0] }, 'unshift');
viral_ok(sub ($x) { my @arr = ( $x ); shift @arr }, 'shift');
viral_ok(sub ($x) { my @arr = ( $x ); pop @arr }, 'pop');
viral_ok(sub ($x) { my @arr; splice @arr, 0, 0, ( $x ); $arr[0] }, 'splice in');
viral_ok(sub ($x) { my @arr = ( $x ); splice @arr, 0, 1 }, 'splice out');

# hash ops
viral_ok(sub ($x) { my %hash = ( key => $x ); ( values %hash )[0] }, 'values');
viral_ok(sub ($x) { my %hash = ( key => $x ); delete $hash{key} }, 'delete');

# other control flow
viral_ok(sub ($x) { my $ret = do { $x; }; $ret }, 'do BLOCK');
viral_ok(sub ($x) { my $ret = eval { $x; }; $ret }, 'eval BLOCK');
viral_ok(sub ($x) {
    use feature 'try';
    try { die $x; }
    catch ($e) { return $e; }
}, 'try/catch' );

# Value-returning UNOPs
sub unop_viral_ok ( $inp, $code, $want_out, $name )
{
    foreach my $round (qw( first second )) {
        my @args = ($inp);
        sv_hook_add($args[0], viral => \"test-val $name $round");

        my $got_out = $code->( @args );
        $round eq "first" and
            is($got_out, $want_out, "$name viral hook yields correct result");

        is_deeply([HkAUXSV_values($got_out, 'viral')], ["test-val $name $round"],
            "$name unop passes viral hook");
    }
}

unop_viral_ok(1, sub ($x) { -$x }, -1, "negate");
unop_viral_ok(1, sub ($x) { ~$x }, ~1, "complement");
unop_viral_ok("abc", sub ($x) { length $x }, 3, "length");

# OP_STRINGIFY is a listop despite only taking 1 argument
# OP_SUBSTR only copies viral magic from the string argument, not the positions
# We can treat both as unops
unop_viral_ok("xyz", sub ($x) { "$x" }, "xyz", "stringify");

unop_viral_ok("xyz", sub ($x) { return substr $x, 1, 1 }, "y", "substr (3arg non-MOD)");
unop_viral_ok("xyz", sub ($x) { return substr $x, 1, 1, "B" }, "y", "substr (4arg non-MOD)");
unop_viral_ok("xyz", sub ($x) { my $ret = "ABC"; substr $ret, 1, 1, $x; $ret; }, "AxyzC", "substr (4arg non-MOD) mutation");
unop_viral_ok("xyz", sub ($x) { my $ret = "ABC"; substr( $ret, 1, 1 ) = $x; $ret; }, "AxyzC", "substr (3arg MOD rewritten)");
# Perl will rewrite a simple  substr($x, $n, $c) = $y  into a 4-arg with
# reördered arguments, so we have to test true lvalue returns via $_
unop_viral_ok("xyz", sub ($x) { my $ret = "ABC"; $_ = $x for substr( $ret, 1, 1 ); $ret; }, "AxyzC", "substr (3arg MOD)");

# OP_SUBSTR_LEFT kicks in if known non-lvalue, offset is constant zero and
# there is no replacement
unop_viral_ok("xyz", sub ($x) { my $ret = substr $x, 0, 2; $ret; }, "xy", "substr_left");

# Inplace-mutating UNOPs; check variable also
sub mut_unop_viral_ok ( $inp, $code, $want_out, $want_outvar, $name )
{
    foreach my $round (qw( first second )) {
        my @args = ($inp);
        sv_hook_add($args[0], viral => \"test-val $name $round");

        my ($got_out, $got_outvar) = $code->( @args );
        $round eq "first" and do {
            is($got_out, $want_out, "$name viral hook yields correct result");
            is($got_outvar, $want_outvar, "$name viral hook yields correct mutation");
        };

        is_deeply([HkAUXSV_values($got_out, 'viral')], ["test-val $name $round"],
            "$name mutating unop passes viral hook");
        is_deeply([HkAUXSV_values($got_outvar, 'viral')], ["test-val $name $round"],
            "$name mutating unop preserves viral hook");
    }
}

mut_unop_viral_ok(1,       sub ($x) { my $ret = ++$x;     $ret, $x }, 2, 2, "preinc");
mut_unop_viral_ok(1,       sub ($x) { my $ret = --$x;     $ret, $x }, 0, 0, "predec");
mut_unop_viral_ok(1,       sub ($x) { my $ret = $x++;     $ret, $x }, 1, 2, "postinc");
mut_unop_viral_ok(1,       sub ($x) { my $ret = $x--;     $ret, $x }, 1, 0, "postdec");
mut_unop_viral_ok("abc",   sub ($x) { my $ret = chop $x;  $ret, $x }, "c", "ab", "chop");
mut_unop_viral_ok("abc\n", sub ($x) { my $ret = chomp $x; $ret, $x }, "1", "abc", "chomp");

# Base-or-UNOPs; which might operate on $_
sub base_or_unop_viral_ok( $inp, $code, $want_out, $name )
{
    foreach my $round (qw( first second )) {
        my @args = ($inp);
        sv_hook_add($args[0], viral => \"test-val $name $round");

        my ($got_base, $got_un) = $code->( ( local $_ ) = @args );
        $round eq "first" and do {
            is($got_base, $want_out, "$name as baseop viral hook yields correct result");
            is($got_un, $want_out, "$name as unop viral hook yields correct result");
        };

        is_deeply([HkAUXSV_values($got_base, 'viral')], ["test-val $name $round"],
            "$name as baseop passes viral hook");
        is_deeply([HkAUXSV_values($got_un, 'viral')], ["test-val $name $round"],
            "$name as unop passes viral hook");
    }
}

use feature 'fc';
base_or_unop_viral_ok("xyz", sub ($x) { uc,      uc $x },      "XYZ", "uc");
base_or_unop_viral_ok("xyz", sub ($x) { ucfirst, ucfirst $x }, "Xyz", "ucfirst");
base_or_unop_viral_ok("XYZ", sub ($x) { lc,      lc $x },      "xyz", "lc");
base_or_unop_viral_ok("XYZ", sub ($x) { lcfirst, lcfirst $x }, "xYZ", "lcfirst");
base_or_unop_viral_ok("xyz", sub ($x) { fc,      fc $x },      fc "xyz", "fc");
base_or_unop_viral_ok("a",   sub ($x) { ord,     ord $x },     ord "a", "ord");
base_or_unop_viral_ok(65,    sub ($x) { chr,     chr $x },     chr 65,  "chr");

sub binop_viral_ok( $in1, $in2, $code, $want_out, $name )
{
    foreach my $round (qw( first second )) {
        my @args;
        my $got_out;

        # Just LHS
        @args = ( $in1, $in2 );
        sv_hook_add($args[0], viral => \"test-val $name LHS $round");

        $got_out = $code->( @args );
        $round eq "first" and
            is($got_out, $want_out, "$name viral hook yields correct result");

        is_deeply([HkAUXSV_values($got_out, 'viral')], ["test-val $name LHS $round"],
            "$name binop passes viral hook from LHS");

        # Just RHS
        @args = ( $in1, $in2 );
        sv_hook_add($args[1], viral => \"test-val $name RHS $round");

        $got_out = $code->( @args );
        is_deeply([HkAUXSV_values($got_out, 'viral')], ["test-val $name RHS $round"],
            "$name binop passes viral hook from RHS");

        # Both
        @args = ( $in1, $in2 );
        sv_hook_add($args[0], viral => \"test-val $name ALLLHS $round");
        sv_hook_add($args[1], viral => \"test-val $name ALLRHS $round");

        $got_out = $code->( @args );
        is_deeply([sort +HkAUXSV_values($got_out, 'viral')],
                  ["test-val $name ALLLHS $round", "test-val $name ALLRHS $round"],
            "$name binop passes viral hook from both args simultaneously");
    }
}

binop_viral_ok(1, 1, sub ($x, $y) { $x +  $y },      2, "add" );
binop_viral_ok(1, 1, sub ($x, $y) { $x += $y; $x },  2, "add mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x -  $y },      0, "subtract" );
binop_viral_ok(1, 1, sub ($x, $y) { $x -= $y; $x },  0, "subtract mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x *  $y },      1, "multiply" );
binop_viral_ok(1, 1, sub ($x, $y) { $x *= $y; $x },  1, "multiply mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x /  $y },      1, "divide" );
binop_viral_ok(1, 1, sub ($x, $y) { $x /= $y; $x },  1, "divide mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x %  $y },      0, "modulo" );
binop_viral_ok(1, 1, sub ($x, $y) { $x %= $y; $x },  0, "modulo mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x **  $y },     1, "power" );
binop_viral_ok(1, 1, sub ($x, $y) { $x **= $y; $x }, 1, "power mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x <<  $y },     2, "left-shift" );
binop_viral_ok(1, 1, sub ($x, $y) { $x <<= $y; $x }, 2, "left-shift mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x >>  $y },     0, "right-shift" );
binop_viral_ok(1, 1, sub ($x, $y) { $x >>= $y; $x }, 0, "right-shift mutating" );

binop_viral_ok(1, 1, sub ($x, $y) { $x &  $y },     1, "bitwise-and" );
binop_viral_ok(1, 1, sub ($x, $y) { $x &= $y; $x }, 1, "bitwise-and mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x |  $y },     1, "bitwise-or" );
binop_viral_ok(1, 1, sub ($x, $y) { $x |= $y; $x }, 1, "bitwise-or mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $x ^  $y },     0, "bitwise-xor" );
binop_viral_ok(1, 1, sub ($x, $y) { $x ^= $y; $x }, 0, "bitwise-xor mutating" );

binop_viral_ok(1, 1, sub ($x, $y) { $x .  $y },         "11", "concat" );
binop_viral_ok(1, 1, sub ($x, $y) { $x .= $y; $x },     "11", "concat mutating" );
binop_viral_ok(1, 1, sub ($x, $y) { $y = $x . $y; $y }, "11", "concat reuse right" );

sub listop_viral_ok ( $argspec, $code, $want_out, $name )
{
    my @argspec = split m//, $argspec;
    my $argc = @argspec;

    foreach my $round (qw( first second )) {
        foreach my $idx ( 0 .. $#argspec ) {
            next unless $argspec[$idx] eq "V";

            my @args = ( "xyz" ) x $argc;
            sv_hook_add($args[$idx], viral => \"test-val $name ARG$idx $round");

            my $got_out = $code->( @args );
            $round eq "first" and
                is($got_out, $want_out, "$name viral hook yields correct result");

            is_deeply([HkAUXSV_values($got_out, 'viral')], ["test-val $name ARG$idx $round"],
                "$name listop passes viral hook from arg[$idx]");
        }

        # Now once more with all args annotated
        if( $argc > 1 ) {
            my @args = ( "xyz" ) x $argc;
            sv_hook_add($args[$_], viral => \"test-val $name ALLARG$_ $round") for 0 .. $#argspec;

            my $got_out = $code->( @args );

            is_deeply([sort +HkAUXSV_values($got_out, 'viral')], [map { "test-val $name ALLARG$_ $round" } ( 0 .. $#argspec )],
                "$name listop passes all viral hooks");
        }
    }
}

listop_viral_ok( "VVV", sub ($sep, @s) { join $sep, @s }, "xyzxyzxyz", "join" );

# OP_MULTICONCAT has many forms
listop_viral_ok( "VV", sub ($x, $y) { "paste ($x) and ($y)" }, "paste (xyz) and (xyz)",
    "multiconcat (padtmp)" );
listop_viral_ok( "VV", sub ($x, $y) { my $ret = "paste ($x) and ($y)"; $ret }, "paste (xyz) and (xyz)",
    "multiconcat (my \$lex)" );
listop_viral_ok( "VV", sub ($x, $y) { my $ret; $ret = "paste ($x) and ($y)"; $ret }, "paste (xyz) and (xyz)",
    "multiconcat (\$lex)" );
listop_viral_ok( "VV", sub ($x, $y) { my @ret; $ret[0] = "paste ($x) and ($y)"; $ret[0] }, "paste (xyz) and (xyz)",
    "multiconcat (\$lex)" );
listop_viral_ok( "VVV", sub ($pre, $x, $y) { my $ret = $pre; $ret .= " and ($x) and ($y)"; $ret }, "xyz and (xyz) and (xyz)",
    "multiconcat (\$lex append)" );

# Perl will turn a simple sprintf with just %s into an OP_MULTICONCAT so we
# have to be more subtle here
listop_viral_ok( "VV", sub ($x, $y) { sprintf "format with %3s and %3s", $x, $y }, "format with xyz and xyz",
    "sprintf" );

sub listret_viral_ok ( $inp, $code, $want_out, $name )
{
    foreach my $round (qw( first second )) {
        my @args = ($inp);
        sv_hook_add($args[0], viral => \"test-val $name $round");

        my $got_out = [ $code->( @args ) ];
        $round eq "first" and
            is_deeply($got_out, $want_out, "$name viral hook yields correct result list");

        foreach my $gotidx ( 0 .. $#$got_out ) {
            is_deeply([HkAUXSV_values($got_out->[$gotidx], 'viral')], ["test-val $name $round"],
                "$name op passes viral hook in result $gotidx");
        }
    }
}

listret_viral_ok("one,two,three", sub ($x) { split m/,/, $x }, [qw( one two three )],
    "split");

done_testing;
