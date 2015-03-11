/*
 * perl_math_int128.h - This file is in the public domain
 * Author: Salvador Fandino <sfandino@yahoo.com>, Dave Rolsky <autarch@urth.org>
 *
 * Generated on: 2015-03-11 11:04:45
 * Math::Int128 version: 0.21
 */

#if !defined (PERL_MATH_INT128_H_INCLUDED)
#define PERL_MATH_INT128_H_INCLUDED

#define MATH_INT128_C_API_REQUIRED_VERSION 1

int perl_math_int128_load(int required_version);

#define PERL_MATH_INT128_LOAD perl_math_int128_load(MATH_INT128_C_API_REQUIRED_VERSION)
#define PERL_MATH_INT128_LOAD_OR_CROAK \
    if (PERL_MATH_INT128_LOAD);        \
    else croak(NULL);

extern HV *math_int128_c_api_hash;
extern int math_int128_c_api_min_version;
extern int math_int128_c_api_max_version;

extern int128_t  (*math_int128_c_api_SvI128)(pTHX_ SV *sv);
#define SvI128(a) ((*math_int128_c_api_SvI128)(aTHX_ (a)))
extern int       (*math_int128_c_api_SvI128OK)(pTHX_ SV*);
#define SvI128OK(a) ((*math_int128_c_api_SvI128OK)(aTHX_ (a)))
extern int128_t  (*math_int128_c_api_SvU128)(pTHX_ SV *sv);
#define SvU128(a) ((*math_int128_c_api_SvU128)(aTHX_ (a)))
extern int       (*math_int128_c_api_SvU128OK)(pTHX_ SV*);
#define SvU128OK(a) ((*math_int128_c_api_SvU128OK)(aTHX_ (a)))
extern SV *      (*math_int128_c_api_newSVi128)(pTHX_ int128_t i128);
#define newSVi128(a) ((*math_int128_c_api_newSVi128)(aTHX_ (a)))
extern SV *      (*math_int128_c_api_newSVu128)(pTHX_ uint128_t u128);
#define newSVu128(a) ((*math_int128_c_api_newSVu128)(aTHX_ (a)))


#endif
