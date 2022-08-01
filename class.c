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

#define newSVobject(fieldcount)  Perl_newSVobject(aTHX_ fieldcount)
SV *
Perl_newSVobject(pTHX_ Size_t fieldcount)
{
    SV *sv = newSV_type(SVt_PVOBJ);

    Newx(AvARRAY((AV *)sv), fieldcount, SV *);
    AvMAX((AV *)sv)  = fieldcount - 1;
    AvFILLp((AV *)sv) = -1;

    return sv;
}

XS(injected_constructor);
XS(injected_constructor)
{
    dXSARGS;

    HV *stash = (HV *)XSANY.any_ptr;
    assert(HvSTASH_IS_CLASS(stash));

    struct xpvhv_aux *aux = HvAUX(stash);

    if((items - 1) % 2)
        Perl_warn(aTHX_ "Odd number of arguments passed to %" HEKf " constructor",
                HEKfARG(HvNAME_HEK(stash)));

    HV *params = NULL;
    if(aux->xhv_class_adjust_blocks) {
        params = newHV();
        SAVEFREESV((SV *)params);

        for(I32 i = 1; i < items; i += 2) {
            SV *name = ST(i);
            SV *val  = (i+1 < items) ? ST(i+1) : &PL_sv_undef;

            /* TODO: think about sanity-checking name for being 
             *   defined
             *   not ref (but overloaded objects?? boo)
             *   not duplicate
             * But then,  %params = @_;  wouldn't do that
             */

            hv_store_ent(params, name, SvREFCNT_inc(val), 0);
        }
    }

    SV *instance = newSVobject(aux->xhv_class_next_fieldix);
    SV *self = sv_2mortal(newRV_noinc(instance));
    sv_bless(self, stash);

    SV **fields = AvARRAY(instance);

    /* create fields */
    for(PADOFFSET fieldix = 0; fieldix < aux->xhv_class_next_fieldix; fieldix++) {
        PADNAME *pn = (PADNAME *)AvARRAY(aux->xhv_class_fields)[fieldix];
        assert(PadnameFIELDINFO(pn)->fieldix == fieldix);

        SV *val = NULL;

        switch(PadnamePV(pn)[0]) {
            case '$':
                val = newSV(0);
                break;

            case '@':
                val = (SV *)newAV();
                break;

            case '%':
                val = (SV *)newHV();
                break;

            default:
                NOT_REACHED;
        }

        fields[fieldix] = val;
        AvFILLp((AV *)instance)++;
    }

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
            mPUSHs(newRV_inc((SV *)params));
            PUTBACK;

            call_sv((SV *)cvp[i], G_VOID);

            FREETMPS;
            LEAVE;
        }
    }

    if(params && hv_iterinit(params) > 0) {
        /* TODO: consider sorting these into a canonical order, but that's awkward */
        HE *he = hv_iternext(params);

        SV *paramnames = newSVsv(HeSVKEY_force(he));
        SAVEFREESV(paramnames);

        while((he = hv_iternext(params)))
            Perl_sv_catpvf(aTHX_ paramnames, ", %" SVf, SVfARG(HeSVKEY_force(he)));

        Perl_croak(aTHX_ "Unrecognised parameters for %" HEKf " constructor: %" SVf,
                HEKfARG(HvNAME_HEK(stash)), SVfARG(paramnames));
    }

    EXTEND(SP, 1);
    ST(0) = self;
    XSRETURN(1);
}

/* OP_METHSTART is an UNOP_AUX whose AUX list contains
 *   [0].uv = count of fieldbinding pairs
 *   [1].uv = maximum fieldidx found in the binding list
 *   [...] = pairs of (padix, fieldix) to bind in .uv fields
 */

/* TODO: People would probably expect to find this in pp.c  ;) */
PP(pp_methstart)
{
    SV *self = av_shift(GvAV(PL_defgv));
    SV *rv = NULL;

    if(!SvROK(self) ||
        !SvOBJECT((rv = SvRV(self))) ||
        SvTYPE(rv) != SVt_PVOBJ)
        /* TODO: check it's in an appropriate class */
        Perl_croak(aTHX_ "Cannot invoke method on a non-instance");

    save_clearsv(&PAD_SVl(PADIX_SELF));
    sv_setsv(PAD_SVl(PADIX_SELF), self);

    UNOP_AUX_item *aux = cUNOP_AUX->op_aux;
    if(aux) {
        assert(SvTYPE(SvRV(self)) == SVt_PVOBJ);
        SV *instance = SvRV(self);
        SV **fieldp = AvARRAY((AV *)instance);

        U32 fieldcount = (aux++)->uv;
        U32 max_fieldix = (aux++)->uv;

        assert(AvFILL(instance)+1 > max_fieldix);

        for(Size_t i = 0; i < fieldcount; i++) {
            PADOFFSET padix   = (aux++)->uv;
            U32       fieldix = (aux++)->uv;

            assert(fieldp[fieldix]);

            /* TODO: There isn't a convenient SAVE macro for doing both these
             * steps in one go. Add one. */
            SAVESPTR(PAD_SVl(padix));
            SV *sv = PAD_SVl(padix) = SvREFCNT_inc(fieldp[fieldix]);
            save_freesv(sv);
        }
    }

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
    HvAUX(stash)->xhv_class_fields        = NULL;
    HvAUX(stash)->xhv_class_next_fieldix  = 0;

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

    CvNOWARN_AMBIGUOUS_on(cv);
    CvIsMETHOD_on(cv);
}

OP *
Perl_class_wrap_method_body(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CLASS_WRAP_METHOD_BODY;

    PADNAMELIST *pnl = PadlistNAMES(CvPADLIST(PL_compcv));

    AV *fieldmap = newAV();
    UV max_fieldix = 0;
    SAVEFREESV((SV *)fieldmap);

    /* padix 0 == @_; padix 1 == $self. Start at 2 */
    for(PADOFFSET padix = 2; padix <= PadnamelistMAX(pnl); padix++) {
        PADNAME *pn = PadnamelistARRAY(pnl)[padix];
        if(!pn || !PadnameIsFIELD(pn))
            continue;

        U32 fieldix = PadnameFIELDINFO(pn)->fieldix;
        if(fieldix > max_fieldix)
            max_fieldix = fieldix;

        av_push(fieldmap, newSVuv(padix));
        av_push(fieldmap, newSVuv(fieldix));
    }

    UNOP_AUX_item *aux = NULL;

    if(av_count(fieldmap)) {
        Newx(aux, 2 + av_count(fieldmap), UNOP_AUX_item);

        UNOP_AUX_item *ap = aux;

        (ap++)->uv = av_count(fieldmap) / 2;
        (ap++)->uv = max_fieldix;

        for(Size_t i = 0; i < av_count(fieldmap); i++)
            (ap++)->uv = SvUV(AvARRAY(fieldmap)[i]);
    }

    /* If this is an empty method body then o will be an OP_STUB and not a
     * list. This will confuse op_sibling_splice() */
    if(o->op_type != OP_LINESEQ)
        o = newLISTOP(OP_LINESEQ, 0, o, NULL);

    op_sibling_splice(o, NULL, 0, newUNOP_AUX(OP_METHSTART, 0, NULL, aux));

    return o;
}

void
Perl_class_add_field(pTHX_ PADNAME *pn)
{
    PERL_ARGS_ASSERT_CLASS_ADD_FIELD;

    assert(HvSTASH_IS_CLASS(PL_curstash));
    struct xpvhv_aux *aux = HvAUX(PL_curstash);

    PADOFFSET fieldix = aux->xhv_class_next_fieldix;
    aux->xhv_class_next_fieldix++;

    Newx(PadnameFIELDINFO(pn), 1, struct padname_fieldinfo);
    PadnameFLAGS(pn) |= PADNAMEf_FIELD;

    PadnameFIELDINFO(pn)->fieldix = fieldix;

    if(!aux->xhv_class_fields)
        aux->xhv_class_fields = newAV();

    av_push(aux->xhv_class_fields, (SV *)pn);
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
