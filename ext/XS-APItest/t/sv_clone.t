#!perl

use v5.42;

use Test::More;
use XS::APItest;

# "leaf" scalars
{
    is sv_clone(12345, 0), 12345,
        'trivial integer clone';
    is sv_clone(1234.5, 0), 1234.5,
        'trivial float clone';
    is sv_clone("hello world", 0), "hello world",
        'trivial string clone';
}

# tree-shaped containers
{
    # technically these all test references as well
    my $copy = sv_clone(my $orig = [1, 2, 3], 0);
    is_deeply $copy, [1, 2, 3],
        'array of integers';
    $orig->[0]++;
    is($copy->[0], 1, 'copy of ARRAY unchanged after orig edited');

    $copy = sv_clone($orig = {one => 1, two => 2}, 0);
    is_deeply $copy, {one => 1, two => 2},
        'hash of integers';
    $orig->{one}++;
    is($copy->{one}, 1, 'copy of HASH unchanged after orig edited');
}

# referential structure is preserved
{
    my $x = [];
    my $y = [$x, $x];
    my $z = [$y, $y];

    my $zcopy = sv_clone($z, 0);

    ok($zcopy->[0] == $zcopy->[1], 'copy retains referential structure [0]');
    my $ycopy = $zcopy->[0];
    ok($ycopy->[0] == $ycopy->[1], 'copy retains referential structure [1]');
}

# internal weakrefs
{
    my $x = [];
    my $y = { strong => $x, weak => $x };
    weaken $y->{weak};

    my $ycopy = sv_clone($y, 0);
    ok(defined $ycopy->{strong} && defined $ycopy->{weak},
        'both refs defined in copy');
    ok(refaddr $ycopy->{strong} == refaddr $ycopy->{weak},
        'both refs point the same way in copy');
    ok(!is_weak $ycopy->{strong} && is_weak $ycopy->{weak},
        'refs have correct strength in copy');
}

# external weakrefs - there's nothing we can do but nuke these
{
    my $outside;

    my $x = [\$outside];
    weaken $x->[0];

    my $xcopy = sv_clone($x, 0);
    ok(!defined $xcopy->[0],
        'externally pointed weakref disappears');
}

# kinda like ref() but returns a plain HASHref to the stash directly
# TODO: add a helper in XS::APItest for this
sub get_SvOBJECT_STASH
{
    use B;
    return B::svref_2object($_[0])->SvSTASH->object_2svref;
}

# blessed references
{
    package Some::HASH::Class {
        sub new { bless [], __PACKAGE__ }
    }

    my $x = Some::HASH::Class->new;
    my $xcopy = sv_clone($x, 0);

    ok(defined $xcopy, 'cloned HV object is defined');
    is(ref $xcopy, "Some::HASH::Class",
        'cloned HV object claims correct package');

    is(refaddr(get_SvOBJECT_STASH($xcopy)), refaddr(get_SvOBJECT_STASH($x)),
        'cloned HV object shares SvSTASH pointer with original');
}

# 5.38-style SVt_PVOBJ
{
    use experimental 'class';
    package Some::OBJECT::Class {
        sub new { bless [], __PACKAGE__ }
    }

    my $x = Some::OBJECT::Class->new;
    my $xcopy = sv_clone($x, 0);

    ok(defined $xcopy, 'cloned OBJ object is defined');
    is(ref $xcopy, "Some::OBJECT::Class",
        'cloned OBJ object claims correct package');

    is(refaddr(get_SvOBJECT_STASH($xcopy)), refaddr(get_SvOBJECT_STASH($x)),
        'cloned OBJ object shares SvSTASH pointer with original');
}

# TODO: So many things
#   Think about all the odd things:
#      GLOBs
#      IOs, etc...
#      CVs - default to referring to subs/closures
#          - consider some flag to emulate Clone::Closure
#          - look at what Future::AsyncAwait or Object::Pad need here

done_testing();
