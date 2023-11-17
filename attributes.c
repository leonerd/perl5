/*    attributes.c
 *
 *    Copyright (C) 2023 by Paul Evans and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/* This file contains the code that implements the registry of attributes for
 * variables, subroutines, and other subjects.
 */

#include "EXTERN.h"
#include "perl.h"

#define split_attr_nameval(sv, namp, valp)  S_split_attr_nameval(aTHX_ sv, namp, valp)
STATIC void
S_split_attr_nameval(pTHX_ SV *sv, SV **namp, SV **valp)
{
    STRLEN svlen = SvCUR(sv);
    bool do_utf8 = SvUTF8(sv);

    const char *paren_at = (const char *)memchr(SvPVX(sv), '(', svlen);
    if(paren_at) {
        STRLEN namelen = paren_at - SvPVX(sv);

        if(SvPVX(sv)[svlen-1] != ')')
            /* Should be impossible to reach this by parsing regular perl code
             * but as apply_attributes() is XS-visible API it might still
             * be reachable. As it's likely unreachable by normal perl code,
             * don't bother listing it in perldiag.
             */
            /* diag_listed_as: SKIPME */
            croak("Malformed attribute string");
        *namp = sv_2mortal(newSVpvn_utf8(SvPVX(sv), namelen, do_utf8));

        const char *value_at = paren_at + 1;
        const char *value_max = SvPVX(sv) + svlen - 2;

        /* TODO: We're only obeying ASCII whitespace here */

        /* Trim whitespace at the start */
        while(value_at < value_max && isSPACE(*value_at))
            value_at += 1;
        while(value_max > value_at && isSPACE(*value_max))
            value_max -= 1;

        if(value_max >= value_at)
            *valp = sv_2mortal(newSVpvn_utf8(value_at, value_max - value_at + 1, do_utf8));
    }
    else {
        *namp = sv;
        *valp = NULL;
    }
}

void
Perl_register_attribute(pTHX_ const char *name, enum AttributeSubject stype,
    U32 flags, AttributeApplyFunction *apply)
{
    PERL_ARGS_ASSERT_REGISTER_ATTRIBUTE;

    struct AttributeDefinition *def;
    Newx(def, 1, struct AttributeDefinition);

    def->name  = name;
    def->stype = stype;
    def->flags = flags;
    def->apply = apply;

    def->next = PL_attribute_definitions;
    PL_attribute_definitions = def;
}

static struct { const char *ucname; const char *name; }
subjectnames[] = {
    [ATTRSUBJECT_NONE]       = { NULL, NULL },
    [ATTRSUBJECT_SUBROUTINE] = { "Subroutine", "subroutine" },
    [ATTRSUBJECT_CLASS]      = { "Class", "class" },
    [ATTRSUBJECT_FIELD]      = { "Field", "field" },
};

STATIC bool
S_apply_attribute(pTHX_ enum AttributeSubject stype, void *subject, OP *attr, bool reject_unknown)
{
    assert(attr->op_type == OP_CONST);
    assert(stype && stype < MAX_ATTRSUBJECT);

    SV *name, *value;
    split_attr_nameval(cSVOPx_sv(attr), &name, &value);

    for(struct AttributeDefinition *def = PL_attribute_definitions; def; def = def->next) {
        if(stype != def->stype)
            continue;

        /* TODO: These attribute names are not UTF-8 aware */
        if(!strEQ(SvPVX(name), def->name))
            continue;

        if(def->flags & ATTRf_MUST_VALUE && !(value && SvOK(value)))
            croak("%s attribute %" SVf " requires a value", subjectnames[stype].ucname, SVfARG(name));
        if(def->flags & ATTRf_NO_VALUE && value && SvOK(value))
            croak("%s attribute %" SVf " does not take a value", subjectnames[stype].ucname, SVfARG(name));

        (*def->apply)(aTHX_ stype, subject, value);
        return true;
    }

    if(reject_unknown)
        croak("Unrecognized %s attribute %" SVf, subjectnames[stype].name, SVfARG(name));

    return false;
}

STATIC OP *
S_apply_attributes(pTHX_ enum AttributeSubject stype, void *subject, OP *attrlist, bool reject_unknown)
{
    if(!attrlist)
        return NULL;
    if(attrlist->op_type == OP_NULL) {
        op_free(attrlist);
        return NULL;
    }

    if(attrlist->op_type != OP_LIST) {
        /* Not in fact a list but just a single attribute */
        if(S_apply_attribute(aTHX_ stype, subject, attrlist, reject_unknown)) {
            op_free(attrlist);
            return NULL;
        }

        return attrlist;
    }

    OP *prev = cLISTOPx(attrlist)->op_first;
    assert(prev->op_type == OP_PUSHMARK);
    OP *o = OpSIBLING(prev);

    OP *next;
    for(; o; o = next) {
        next = OpSIBLING(o);

        if(S_apply_attribute(aTHX_ stype, subject, o, reject_unknown)) {
            op_sibling_splice(attrlist, prev, 1, NULL);
            op_free(o);
        }
        else {
            prev = o;
        }
    }

    if(OpHAS_SIBLING(cLISTOPx(attrlist)->op_first))
        return attrlist;

    /* The list is now entirely empty, we might as well discard it */
    op_free(attrlist);
    return NULL;
}

void
Perl_apply_attributes(pTHX_ enum AttributeSubject stype, void *subject, OP *attrlist)
{
    PERL_ARGS_ASSERT_APPLY_ATTRIBUTES;

    /* ignore the return value as it'll always be NULL by now */
    S_apply_attributes(aTHX_ stype, subject, attrlist, true);
}

OP *
Perl_apply_known_attributes(pTHX_ enum AttributeSubject stype, void *subject, OP *attrlist)
{
    PERL_ARGS_ASSERT_APPLY_KNOWN_ATTRIBUTES;

    return S_apply_attributes(aTHX_ stype, subject, attrlist, false);
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
