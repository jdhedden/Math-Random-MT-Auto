/*
 * Math::Random::MT::Auto
 * Copyright 2005 Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "mt19937ar.h"

#define MY_CXT_KEY "Math::Random::MT::Auto::_guts" XS_VERSION

START_MY_CXT

MODULE = Math::Random::MT::Auto   PACKAGE = Math::Random::MT::Auto
PROTOTYPES: DISABLE

BOOT:
{
    MY_CXT_INIT;
}

void
seed(array, ...)
    PREINIT:
        dMY_CXT;
        SV *tmp;
        U32 *seed;
        int ii;
    CODE:
        tmp = NEWSV(0, items*sizeof(U32));
        seed = (U32 *)SvPVX(tmp);
        for (ii=0; ii < items; ii++) {
            seed[ii] = SvUV(ST(ii));
        }
        mt_seed(&MY_CXT, seed, items);
        sv_2mortal(tmp);

U32
rand32()
    PREINIT:
        dMY_CXT;
    CODE:
        RETVAL = mt_rand32(&MY_CXT);
    OUTPUT:
        RETVAL

double
rand(...)
    PREINIT:
        dMY_CXT;
    CODE:
        RETVAL = (double)mt_rand32(&MY_CXT) / 4294967296.0;
        if (items >= 1) {
            RETVAL *= SvNV(ST(0));
        }
    OUTPUT:
        RETVAL
