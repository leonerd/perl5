/*    class.c
 *
 *    Copyright (C) 2022 by Paul Evans and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/* This file contains the code that implements perl's new `use feature 'class'`
 * object model
 */

#include "EXTERN.h"
#include "perl.h"

#include "XSUB.h"

XS(injected_constructor);
XS(injected_constructor)
{
    dXSARGS;

    HV *stash = (HV *)XSANY.any_ptr;

    SV *self = sv_2mortal(newRV_noinc((SV *)newAV()));
    sv_bless(self, stash);

    EXTEND(SP, 1);
    ST(0) = self;
    XSRETURN(1);
}

static void
invoke_class_seal(pTHX_ void *_arg)
{
    class_seal_stash((HV *)_arg);
}

void
Perl_class_setup_stash(pTHX_ HV *stash)
{
    PERL_ARGS_ASSERT_CLASS_SETUP_STASH;

    char *classname = HvNAME(stash);
    U32 nameflags = HvNAMEUTF8(stash) ? SVf_UTF8 : 0;

    /* TODO:
     *   Set some kind of flag on the stash to point out it's a class
     *   Allocate storage for all the extra things a class needs
     *     See https://github.com/leonerd/perl5/discussions/1
     */

    /* Inject the constructor */
    {
        SV *newname = Perl_newSVpvf(aTHX_ "%s::new", classname);
        SAVEFREESV(newname);

        CV *newcv = newXS_flags(SvPV_nolen(newname), injected_constructor, __FILE__, NULL, nameflags);
        CvXSUBANY(newcv).any_ptr = stash;
    }

    /* TODO:
     *   DOES method
     */

    SAVEDESTRUCTOR_X(invoke_class_seal, stash);
}

void
Perl_class_seal_stash(pTHX_ HV *stash)
{
    PERL_ARGS_ASSERT_CLASS_SEAL_STASH;

    /* TODO: anything? */
}

void
Perl_class_prepare_method_parse(pTHX_ CV *cv)
{
    PERL_ARGS_ASSERT_CLASS_PREPARE_METHOD_PARSE;

    assert(cv == PL_compcv);

    /* We expect this to be at the start of sub parsing, so there won't be
     * anything in the pad yet
     */
    assert(PL_comppad_name_fill == 0);

    PADOFFSET padix;

    padix = pad_add_name_pvs("$self", 0, NULL, NULL);
    assert(padix == 1);

    intro_my();
}

OP *
Perl_class_wrap_method_body(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CLASS_WRAP_METHOD_BODY;

    /* Inject  my $self = shift;  at the start */

    OP *padsvop = newOP(OP_PADSV, OPf_REF|OPf_MOD|OPf_SPECIAL);
    padsvop->op_targ = 1;
    padsvop->op_private |= OPpLVAL_INTRO;

    OP *assignop = newBINOP(OP_SASSIGN, 0,
        newOP(OP_SHIFT, OPf_SPECIAL),
        padsvop);

    op_sibling_splice(o, NULL, 0, assignop);

    return o;
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
