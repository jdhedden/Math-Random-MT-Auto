/* Mersenne Twister PRNG

   A C-Program for MT19937 (32- and 64-bit versions), with initialization
   improved 2002/1/26.  Coded by Takuji Nishimura and Makoto Matsumoto,
   and including Shawn Cokus's optimizations.

   Copyright (C) 1997 - 2004, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.
   Copyright (C) 2005, Mutsuo Saito, All rights reserved.
   Copyright 2005 Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

     1. Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

     2. Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

     3. The names of its contributors may not be used to endorse or promote
        products derived from this software without specific prior written
        permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER
   OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

   Any feedback is very welcome.
   <m-mat AT math DOT sci DOT hiroshima-u DOT ac DOT jp>
   http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html
*/

/* Gaussian Function

   Lower tail quantile for standard normal distribution function.

   This function returns an approximation of the inverse cumulative
   standard normal distribution function.  I.e., given P, it returns
   an approximation to the X satisfying P = Pr{Z <= X} where Z is a
   random variable from the standard normal distribution.

   The algorithm uses a minimax approximation by rational functions
   and the result has a relative error whose absolute value is less
   than 1.15e-9.

   Author: Peter J. Acklam
   http://home.online.no/~pjacklam/notes/invnorm/
   C implementation by V. Natarajan
   Released to public domain
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <stdlib.h>
#include <math.h>


/* Constants used in X_gaussian() */
#define  A1  (-3.969683028665376e+01)
#define  A2    2.209460984245205e+02
#define  A3  (-2.759285104469687e+02)
#define  A4    1.383577518672690e+02
#define  A5  (-3.066479806614716e+01)
#define  A6    2.506628277459239e+00

#define  B1  (-5.447609879822406e+01)
#define  B2    1.615858368580409e+02
#define  B3  (-1.556989798598866e+02)
#define  B4    6.680131188771972e+01
#define  B5  (-1.328068155288572e+01)

#define  C1  (-7.784894002430293e-03)
#define  C2  (-3.223964580411365e-01)
#define  C3  (-2.400758277161838e+00)
#define  C4  (-2.549732539343734e+00)
#define  C5    4.374664141464968e+00
#define  C6    2.938163982698783e+00

#define  D1    7.784695709041462e-03
#define  D2    3.224671290700398e-01
#define  D3    2.445134137142996e+00
#define  D4    3.754408661907416e+00

#define P_LOW   0.02425
/* P_HIGH = 1 - P_LOW */
#define P_HIGH  0.97575


/* Constants related to the Mersenne Twister */
#if UVSIZE == 8
#   define N 312
#   define M 156

#   define MIXBITS(u,v) ( ((u) & 0xFFFFFFFF80000000ULL) | ((v) & 0x7FFFFFFFULL) )
#   define TWIST(u,v) ((MIXBITS(u,v) >> 1) ^ ((v)&1UL ? 0xB5026F5AA96619E9ULL : 0ULL))

#   define TEMPER_ELEM(x)                       \
        x ^= (x >> 29) & 0x0000000555555555ULL; \
        x ^= (x << 17) & 0x71D67FFFEDA60000ULL; \
        x ^= (x << 37) & 0xFFF7EEE000000000ULL; \
        x ^= (x >> 43)

    /* Seed routine constants */
#   define BIT_SHIFT 62
#   define MAGIC1 6364136223846793005ULL
#   define MAGIC2 3935559000370003845ULL
#   define MAGIC3 2862933555777941757ULL
#   define HI_BIT 1ULL<<63

#   define TWOeMINUS52 2.22044604925031308085e-016
    /* Make a double between 0 (inclusive) and 1 (exclusive) */
#   define MAKE_0_1(x) (((x) >> 12) * TWOeMINUS52)

    /* Make a double between 0 and 1 (exclusive) */
#   define BETWEEN_0_1(x) ((((x) >> 12) * TWOeMINUS52) + (TWOeMINUS52 / 2))

#else
#   define N 624
#   define M 397

#   define MIXBITS(u,v) ( ((u) & 0x80000000) | ((v) & 0x7FFFFFFF) )
#   define TWIST(u,v) ((MIXBITS((u),(v)) >> 1) ^ (((v)&1UL) ? 0x9908B0DF : 0UL))

#   define TEMPER_ELEM(x)            \
        x ^= (x >> 11);              \
        x ^= (x << 7)  & 0x9D2C5680; \
        x ^= (x << 15) & 0xEFC60000; \
        x ^= (x >> 18)

    /* Seed routine constants */
#   define BIT_SHIFT 30
#   define MAGIC1 1812433253
#   define MAGIC2 1664525
#   define MAGIC3 1566083941
#   define HI_BIT 0x80000000

#   define TWOeMINUS32 2.32830643653869628906e-010
    /* Make a double between 0 (inclusive) and 1 (exclusive) */
#   define MAKE_0_1(x) ((double)(x) * TWOeMINUS32)

    /* Make a double between 0 and 1 (exclusive) */
#   define BETWEEN_0_1(x) (((double)(x) + 0.5) * TWOeMINUS32)
#endif

/* Get next element from the PRNG */
#define NEXT_ELEM(x) ((--x.left == 0) ? _mt_algo(&x) : *x.next++)
#define NEXT_ELEM_PTR(x) ((--x->left == 0) ? _mt_algo(x) : *x->next++)


/* The PRNG state structure */
struct mt {
    UV state[N];
    UV *next;
    int left;
};

typedef struct mt my_cxt_t;
typedef struct mt *Math__Random__MT__Auto;


/* The guts of the Mersenne Twister algorithm */
static UV
_mt_algo(my_cxt_t *self)
{
    UV *st = self->state;
    UV *sn = &st[2];
    UV *sx = &st[M];
    UV n0 = st[0];
    UV n1 = st[1];
    int kk;

    for (kk = N-M+1;  --kk;  n0 = n1, n1 = *sn++) {
        *st++ = *sx++ ^ TWIST(n0, n1);
    }
    sx = self->state;
    for (kk = M;      --kk;  n0 = n1, n1 = *sn++) {
        *st++ = *sx++ ^ TWIST(n0, n1);
    }
    n1 = *self->state;
    *st = *sx ^ TWIST(n0, n1);

    self->next = &self->state[1];
    self->left = N;

    return (n1);
}


/* Seed the PRNG */
static void
_mt_seed(my_cxt_t *self, UV *seed, int len)
{
    int ii, jj, kk;
    UV *st = self->state;

    /* Initialize */
    st[0]= 19650218;
    for (ii=1; ii<N; ii++) {
        st[ii] = (MAGIC1 * (st[ii-1] ^ (st[ii-1] >> BIT_SHIFT)) + ii);
    }

    /* Add supplied seed */
    ii=1; jj=0;
    for (kk = ((N>len) ? N : len); kk; kk--) {
        st[ii] = (st[ii] ^ ((st[ii-1] ^ (st[ii-1] >> BIT_SHIFT)) * MAGIC2))
                        + seed[jj] + jj;
        if (++ii >= N) { st[0] = st[N-1]; ii=1; }
        if (++jj >= len) jj=0;
    }

    /* Final shuffle */
    for (kk=N-1; kk; kk--) {
        st[ii] = (st[ii] ^ ((st[ii-1] ^ (st[ii-1] >> BIT_SHIFT)) * MAGIC3)) - ii;
        if (++ii >= N) { st[0] = st[N-1]; ii=1; }
    }

    /* Guarantee non-zero initial state */
    st[0] = HI_BIT;

    /* Forces twist when first random is requested */
    self->left = 1;
}


#define MY_CXT_KEY "Math::Random::MT::Auto::_guts" XS_VERSION

START_MY_CXT

MODULE = Math::Random::MT::Auto   PACKAGE = Math::Random::MT::Auto
PROTOTYPES: DISABLE

BOOT:
{
    MY_CXT_INIT;
}

Math::Random::MT::Auto
SA_prng()
    PREINIT:
        dMY_CXT;
    CODE:
        /* These initializations ensure that the PRNG is 'safe' */
        MY_CXT.state[0] = HI_BIT;
        MY_CXT.left = 1;
        RETVAL = &MY_CXT;
    OUTPUT:
        RETVAL

UV
mt_irand(...)
    PREINIT:
        dMY_CXT;
    CODE:
        /* Random number on [0,0xFFFFFFFF] interval */
        RETVAL = NEXT_ELEM(MY_CXT);
        TEMPER_ELEM(RETVAL);
    OUTPUT:
        RETVAL

double
mt_rand(...)
    PREINIT:
        dMY_CXT;
        UV rand;
    CODE:
        /* Random number on [0,1) interval */
        rand = NEXT_ELEM(MY_CXT);
        TEMPER_ELEM(rand);
        RETVAL = MAKE_0_1(rand);
        if (items >= 1) {
            /* Random number on [0,X) interval */
            RETVAL *= SvNV(ST(0));
        }
    OUTPUT:
        RETVAL

Math::Random::MT::Auto
OO_prng()
    CODE:
        /* Create new PRNG for OO interface */
        RETVAL = malloc(sizeof(my_cxt_t));
    OUTPUT:
        RETVAL

UV
irand(rand_obj)
        HV *rand_obj
    PREINIT:
        IV tmp;
        my_cxt_t *prng;
    CODE:
        /* Extract PRNG context from object */
        tmp = SvIV((SV*)SvRV(*hv_fetch(rand_obj, "PRNG", 4, 0)));
        prng = INT2PTR(my_cxt_t *, tmp);

        /* Random number on [0,0xFFFFFFFF] interval */
        RETVAL = NEXT_ELEM_PTR(prng);
        TEMPER_ELEM(RETVAL);
    OUTPUT:
        RETVAL

double
rand(rand_obj, ...)
        HV *rand_obj
    PREINIT:
        IV tmp;
        my_cxt_t *prng;
        UV rand;
    CODE:
        /* Extract PRNG context from object */
        tmp = SvIV((SV*)SvRV(*hv_fetch(rand_obj, "PRNG", 4, 0)));
        prng = INT2PTR(my_cxt_t *, tmp);

        /* Random number on [0,1) interval */
        rand = NEXT_ELEM_PTR(prng);
        TEMPER_ELEM(rand);
        RETVAL = MAKE_0_1(rand);
        if (items >= 2) {
            /* Random number on [0,X) interval */
            RETVAL *= SvNV(ST(1));
        }
    OUTPUT:
        RETVAL

void
OO_DESTROY(prng)
        Math::Random::MT::Auto prng
    PREINIT:
        dMY_CXT;
    CODE:
        /* Object cleanup */
        if (prng && (prng != &MY_CXT)) {
            free(prng);
        }

void
X_seed(prng, seed)
        Math::Random::MT::Auto prng
        AV *seed
    PREINIT:
        int ii;
        int len;
        UV *buff;
    CODE:
        /* Length of the seed */
        len = av_len(seed)+1;
        /* Copy the seed */
        buff = (UV *)malloc(len * sizeof(UV));
        for (ii=0; ii < len; ii++) {
            buff[ii] = SvUV(*av_fetch(seed, ii, 0));
        }
        /* Set up the PRNG */
        _mt_seed(prng, buff, len);
        /* Cleanup */
        free(buff);

SV *
X_get_state(prng)
        Math::Random::MT::Auto prng
    PREINIT:
        int ii;
        AV *state;
    CODE:
        /* Returns array ref containing PRNG state vector */
        state = newAV();
        for (ii=0; ii<N; ii++) {
            av_push(state, newSVuv(prng->state[ii]));
        }
        av_push(state, newSViv(prng->left));
        RETVAL = newRV((SV *)state);
    OUTPUT:
        RETVAL

void
X_set_state(prng, state)
        Math::Random::MT::Auto prng
        AV *state
    PREINIT:
        int ii;
    CODE:
        /* Sets PRNG state vector from input array ref */
        for (ii=0; ii<N; ii++) {
            prng->state[ii] = SvUV(*av_fetch(state, ii, 0));
        }
        prng->left = SvIV(*av_fetch(state, N, 0));
        if (prng->left > 1) {
            prng->next = &prng->state[(N+1) - prng->left];
        }

double
gaussian(...)
    PREINIT:
        dMY_CXT;
        HV *rand_obj;
        IV tmp;
        my_cxt_t *prng;
        UV y;
        double p, q, r;
        int idx = 0;
    CODE:
        if (items && SvROK(ST(0))) {
            /* OO interface */
            rand_obj = (HV*)SvRV(ST(0));
            tmp = SvIV((SV*)SvRV(*hv_fetch(rand_obj, "PRNG", 4, 0)));
            prng = INT2PTR(my_cxt_t *, tmp);

            items--;
            idx = 1;

            /* Get random integer from OO PRNG*/
            y = NEXT_ELEM_PTR(prng);

        } else {
            /* Get random integer from standalone PRNG*/
            y = NEXT_ELEM(MY_CXT);
        }

        TEMPER_ELEM(y);
        p = BETWEEN_0_1(y);

        /* Normal distribution with SD = 1 and mean = 0 */
        if (p < P_LOW) {
            q = sqrt(-2*log(p));
            RETVAL = (((((C1*q+C2)*q+C3)*q+C4)*q+C5)*q+C6) /
                      ((((D1*q+D2)*q+D3)*q+D4)*q+1);

        } else if ((P_LOW <= p) && (p <= P_HIGH)){
            q = p - 0.5;
            r = q*q;
            RETVAL = (((((A1*r+A2)*r+A3)*r+A4)*r+A5)*r+A6)*q /
                     (((((B1*r+B2)*r+B3)*r+B4)*r+B5)*r+1);

        } else {
            q = sqrt(-2*log(1-p));
            RETVAL = -(((((C1*q+C2)*q+C3)*q+C4)*q+C5)*q+C6) /
                       ((((D1*q+D2)*q+D3)*q+D4)*q+1);
        }

        if (items) {
            /* Normal distribution with SD = X */
            RETVAL *= SvNV(ST(idx));
            if (items > 1) {
                /* Normal distribution with mean = Y */
                RETVAL += SvNV(ST(idx+1));
            }
        }
    OUTPUT:
        RETVAL
