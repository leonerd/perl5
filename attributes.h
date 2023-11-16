/*    attributes.h
 *
 *    Copyright (C) 2023, by Paul Evans and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

enum AttributeSubject {
  ATTRSUBJECT_NONE,
  /* TODO: Some core perl things like lexical/package variables, ... */
  ATTRSUBJECT_SUBROUTINE, /* subject is CV * */
  ATTRSUBJECT_CLASS,      /* subject is HV * */
  ATTRSUBJECT_FIELD,      /* subject is PADNAME * */

  MAX_ATTRSUBJECT /* must be last */
};

#define ATTRf_MUST_VALUE (1<<0)
#define ATTRf_NO_VALUE   (1<<1)

typedef void AttributeApplyFunction(pTHX_ enum AttributeSubject stype, void *subject, SV *value);

void Perl_register_attribute(pTHX_ const char *name, enum AttributeSubject stype,
    U32 flags, AttributeApplyFunction *apply);

/* As seen in PL_attribute_definitions */
struct AttributeDefinition;
struct AttributeDefinition {
    struct AttributeDefinition *next;
    const char *name;
    enum AttributeSubject stype;
    U32 flags;
    void (*apply)(pTHX_ enum AttributeSubject stype, void *subject, SV *value);
};

/* attr must be an OP_CONST */
void Perl_apply_attribute(pTHX_ enum AttributeSubject stype, void *subject, OP *attr);

/* attrlist must be an OP_LIST of OP_CONST */
void Perl_apply_attributes(pTHX_ enum AttributeSubject stype, void *subject, OP *attrlist);
