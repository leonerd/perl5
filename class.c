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

enum {
    PADIX_SELF = 1,
};

void
Perl_croak_kw_unless_class(pTHX_ const char *kw)
{
    PERL_ARGS_ASSERT_CROAK_KW_UNLESS_CLASS;

    if(!HvSTASH_IS_CLASS(PL_curstash))
        Perl_croak(aTHX_ "Cannot '%s' outside of a 'class'", kw);
}

XS(injected_constructor);
XS(injected_constructor)
{
    dXSARGS;

    HV *stash = (HV *)XSANY.any_ptr;
    assert(HvSTASH_IS_CLASS(stash));

    struct xpvhv_aux *aux = HvAUX(stash);

    SV *self = sv_2mortal(newRV_noinc((SV *)newAV()));
    sv_bless(self, stash);

    if(aux->xhv_class_adjust_blocks) {
        CV **cvp = (CV **)AvARRAY(aux->xhv_class_adjust_blocks);
        U32 nblocks = av_count(aux->xhv_class_adjust_blocks);

        for(U32 i = 0; i < nblocks; i++) {
            ENTER;
            SAVETMPS;
            SPAGAIN;

            EXTEND(SP, 1);

            PUSHMARK(SP);
            PUSHs(self);  /* I don't believe this needs to be an sv_mortalcopy() */
            PUTBACK;

            call_sv((SV *)cvp[i], G_VOID);

            FREETMPS;
            LEAVE;
        }
    }

    EXTEND(SP, 1);
    ST(0) = self;
    XSRETURN(1);
}

/* TODO: People would probably expect to find this in pp.c  ;) */
PP(pp_methstart)
{
    SV *self = av_shift(GvAV(PL_defgv));

    /* TODO: much sanity checking on self */

    save_clearsv(&PAD_SVl(PADIX_SELF));
    sv_setsv(PAD_SVl(PADIX_SELF), self);

    return NORMAL;
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

    assert(HvHasAUX(stash));

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

    HvAUX(stash)->xhv_class_adjust_blocks = NULL;
    HvAUX(stash)->xhv_aux_flags |= HvAUXf_IS_CLASS;

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
    assert(HvSTASH_IS_CLASS(PL_curstash));

    /* We expect this to be at the start of sub parsing, so there won't be
     * anything in the pad yet
     */
    assert(PL_comppad_name_fill == 0);

    PADOFFSET padix;

    padix = pad_add_name_pvs("$self", 0, NULL, NULL);
    assert(padix == PADIX_SELF);

    intro_my();
}

OP *
Perl_class_wrap_method_body(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CLASS_WRAP_METHOD_BODY;

    /* If this is an empty method body then o will be an OP_STUB and not a
     * list. This will confuse op_sibling_splice() */
    if(o->op_type != OP_LINESEQ)
        o = newLISTOP(OP_LINESEQ, 0, o, NULL);

    op_sibling_splice(o, NULL, 0, newOP(OP_METHSTART, 0));

    return o;
}

void
Perl_class_add_ADJUST(pTHX_ CV *cv)
{
    PERL_ARGS_ASSERT_CLASS_ADD_ADJUST;

    assert(HvSTASH_IS_CLASS(PL_curstash));
    struct xpvhv_aux *aux = HvAUX(PL_curstash);

    if(!aux->xhv_class_adjust_blocks)
        aux->xhv_class_adjust_blocks = newAV();

    av_push(aux->xhv_class_adjust_blocks, (SV *)cv);
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
