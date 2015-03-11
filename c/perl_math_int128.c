/*
 * perl_math_int128.c - This file is in the public domain
 * Author: Salvador Fandino <sfandino@yahoo.com>, Dave Rolsky <autarch@urth.org>
 *
 * Generated on: 2015-03-11 11:04:45
 * Math::Int128 version: 0.21
 */

#include "EXTERN.h"
#include "perl.h"
#include "ppport.h"

#if ((__GNUC__ == 4) && (__GNUC_MINOR__ < 6))

/* workaroung for gcc 4.4/4.5 - see http://gcc.gnu.org/gcc-4.4/changes.html */
typedef int int128_t __attribute__ ((__mode__ (TI)));
typedef unsigned int uint128_t __attribute__ ((__mode__ (TI)));

#else

typedef __int128 int128_t;
typedef unsigned __int128 uint128_t;

#endif


HV *math_int128_c_api_hash = NULL;
int math_int128_c_api_min_version = 0;
int math_int128_c_api_max_version = 0;

int128_t  (*math_int128_c_api_SvI128)(pTHX_ SV *sv) = NULL;
int       (*math_int128_c_api_SvI128OK)(pTHX_ SV*) = NULL;
int128_t  (*math_int128_c_api_SvU128)(pTHX_ SV *sv) = NULL;
int       (*math_int128_c_api_SvU128OK)(pTHX_ SV*) = NULL;
SV *      (*math_int128_c_api_newSVi128)(pTHX_ int128_t i128) = NULL;
SV *      (*math_int128_c_api_newSVu128)(pTHX_ uint128_t u128) = NULL;

int
perl_math_int128_load(int required_version) {
    dTHX;
    SV **svp;

    eval_pv("require Math::Int128", TRUE);
    if (SvTRUE(ERRSV)) return 0;

    math_int128_c_api_hash = get_hv("Math::Int128::C_API", 0);
    if (!math_int128_c_api_hash) {
        sv_setpv_mg(ERRSV, "Unable to load Math::Int128 C API");
        return 0;
    }

    math_int128_c_api_min_version = SvIV(*hv_fetch(math_int128_c_api_hash, "min_version", 11, 1));
    math_int128_c_api_max_version = SvIV(*hv_fetch(math_int128_c_api_hash, "max_version", 11, 1));
    if ((required_version < math_int128_c_api_min_version) ||
        (required_version > math_int128_c_api_max_version)) {
        sv_setpvf_mg(ERRSV, 
                     "Math::Int128 C API version mismatch. "
                     "The installed module supports versions %d to %d but %d is required",
                     math_int128_c_api_min_version,
                     math_int128_c_api_max_version,
                     required_version);
        return 0;
    }

    svp = hv_fetch(math_int128_c_api_hash, "SvI128", 6, 0);
    if (!svp || !*svp) {
        sv_setpv_mg(ERRSV, "Unable to fetch pointer 'SvI128' C function from Math::Int128");
        return 0;
    }
    math_int128_c_api_SvI128 = INT2PTR(void *, SvIV(*svp));
    svp = hv_fetch(math_int128_c_api_hash, "SvI128OK", 8, 0);
    if (!svp || !*svp) {
        sv_setpv_mg(ERRSV, "Unable to fetch pointer 'SvI128OK' C function from Math::Int128");
        return 0;
    }
    math_int128_c_api_SvI128OK = INT2PTR(void *, SvIV(*svp));
    svp = hv_fetch(math_int128_c_api_hash, "SvU128", 6, 0);
    if (!svp || !*svp) {
        sv_setpv_mg(ERRSV, "Unable to fetch pointer 'SvU128' C function from Math::Int128");
        return 0;
    }
    math_int128_c_api_SvU128 = INT2PTR(void *, SvIV(*svp));
    svp = hv_fetch(math_int128_c_api_hash, "SvU128OK", 8, 0);
    if (!svp || !*svp) {
        sv_setpv_mg(ERRSV, "Unable to fetch pointer 'SvU128OK' C function from Math::Int128");
        return 0;
    }
    math_int128_c_api_SvU128OK = INT2PTR(void *, SvIV(*svp));
    svp = hv_fetch(math_int128_c_api_hash, "newSVi128", 9, 0);
    if (!svp || !*svp) {
        sv_setpv_mg(ERRSV, "Unable to fetch pointer 'newSVi128' C function from Math::Int128");
        return 0;
    }
    math_int128_c_api_newSVi128 = INT2PTR(void *, SvIV(*svp));
    svp = hv_fetch(math_int128_c_api_hash, "newSVu128", 9, 0);
    if (!svp || !*svp) {
        sv_setpv_mg(ERRSV, "Unable to fetch pointer 'newSVu128' C function from Math::Int128");
        return 0;
    }
    math_int128_c_api_newSVu128 = INT2PTR(void *, SvIV(*svp));

    return 1;
}

