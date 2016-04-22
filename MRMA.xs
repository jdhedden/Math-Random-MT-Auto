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

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <stdlib.h>
#include <math.h>


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

    /* Various powers of 2 */
#   define TWOeMINUS51 4.44089209850062616169452667236328125e-16
#   define TWOeMINUS52 2.220446049250313080847263336181640625e-16
#   define TWOeMINUS53 1.1102230246251565404236316680908203125e-16

    /* Make a double between 0 (inclusive) and 1 (exclusive) */
#   define RAND_0i_1x(x) (((NV)((x) >> 12)) * TWOeMINUS52)
    /* Make a double between 0 and 1 (exclusive) */
#   define RAND_0x_1x(x)   (RAND_0i_1x(x) + TWOeMINUS53)
    /* Make a double between 0 (exclusive) and 1 (inclusive) */
#   define RAND_0x_1i(x) (((NV)(((x) >> 12) + 1)) * TWOeMINUS52)
    /* Make a double between -1 and 1 (exclusive) */
#   define RAND_NEG1x_1x(x) ((((NV)(((IV)(x)) >> 11)) * TWOeMINUS52) + TWOeMINUS53)

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

    /* Various powers of 2 */
#   define TWOeMINUS31 4.656612873077392578125e-10
#   define TWOeMINUS32 2.3283064365386962890625e-10
#   define TWOeMINUS33 1.16415321826934814453125e-10

    /* Make a double between 0 (inclusive) and 1 (exclusive) */
#   define RAND_0i_1x(x) ((NV)(x) * TWOeMINUS32)
    /* Make a double between 0 and 1 (exclusive) */
#   define RAND_0x_1x(x)   (RAND_0i_1x(x) + TWOeMINUS33)
    /* Make a double between 0 (exclusive) and 1 (inclusive) */
#   define RAND_0x_1i(x) ((((NV)(x)) + 1.0) * TWOeMINUS32)
    /* Make a double between -1 and 1 (exclusive) */
#   define RAND_NEG1x_1x(x) ((((NV)((IV)(x))) * TWOeMINUS31) + TWOeMINUS32)
#endif

#define PI 3.1415926535897932

/* Get next element from the PRNG */
#define NEXT_ELEM(x) ((--x.left == 0) ? _mt_algo(&x) : *x.next++)
#define NEXT_ELEM_PTR(x) ((--x->left == 0) ? _mt_algo(x) : *x->next++)

/* Get PRNG struct from object for OO interface */
#define EXTRACT_PRNG(obj) \
        tmp = SvIV((SV*)SvRV(*hv_fetch(obj, "PRNG", 4, 0)));            \
        prng = INT2PTR(my_cxt_t *, tmp)

/* Variable declarations for OO and functional interfaces */
#define PRNG_VARS       \
        dMY_CXT;        \
        HV *rand_obj;   \
        IV tmp;         \
        my_cxt_t *prng; \
        int idx = 0;

/* Sets up PRNG for OO and functional interfaces */
#define PRNG_PREP \
        if (items && SvROK(ST(0)) && SvTYPE(SvRV(ST(0)))==SVt_PVHV) {   \
            /* OO interface */                                          \
            rand_obj = (HV*)SvRV(ST(0));                                \
            /* prng = */ EXTRACT_PRNG(rand_obj);                        \
            items--;                                                    \
            idx = 1;                                                    \
        } else {                                                        \
            /* Standalone PRNG */                                       \
            prng = &MY_CXT;                                             \
        }


/* The PRNG state structure */
struct mt {
    UV state[N];
    UV *next;
    IV left;

    struct {
        IV have;
        NV value;
    } gaussian;

    struct {
        NV mean;
        NV log_mean;
        NV sqrt2mean;
        NV term;
    } poisson;

    struct {
        IV trials;
        NV term;
        NV prob;
        NV plog;
        NV pclog;
    } binomial;
};

typedef struct mt my_cxt_t;
typedef struct mt *Math__Random__MT__Auto___PRNG_;


/* The guts of the Mersenne Twister algorithm */
static UV
_mt_algo(my_cxt_t *prng)
{
    UV *st = prng->state;
    UV *sn = &st[2];
    UV *sx = &st[M];
    UV n0 = st[0];
    UV n1 = st[1];
    int kk;

    for (kk = N-M+1;  --kk;  n0 = n1, n1 = *sn++) {
        *st++ = *sx++ ^ TWIST(n0, n1);
    }
    sx = prng->state;
    for (kk = M;      --kk;  n0 = n1, n1 = *sn++) {
        *st++ = *sx++ ^ TWIST(n0, n1);
    }
    n1 = *prng->state;
    *st = *sx ^ TWIST(n0, n1);

    prng->next = &prng->state[1];
    prng->left = N;

    return (n1);
}


/* Helper function to get next random double */
static NV
_rand(my_cxt_t *prng)
{
    UV x = NEXT_ELEM_PTR(prng);
    TEMPER_ELEM(x);
    return (RAND_0x_1x(x));
}


/* Helper function - returns the value ln(gamma(x)) for x > 0 */
/* Optimized from 'Numerical Recipes in C', Chapter 6.1 */
static NV
_ln_gamma(NV x)
{
    NV qq, ser;

    qq  = x + 4.5;
    qq -= (x - 0.5) * log(qq);

    ser = 1.000000000190015
        + (76.18009172947146     / x)
        - (86.50532032941677     / (x + 1.0))
        + (24.01409824083091     / (x + 2.0))
        - (1.231739572450155     / (x + 3.0))
        + (0.1208650973866179e-2 / (x + 4.0))
        - (0.5395239384953e-5    / (x + 5.0));

    return (log(2.5066282746310005 * ser) - qq);
}


#define MY_CXT_KEY "Math::Random::MT::Auto::_guts" XS_VERSION

START_MY_CXT

MODULE = Math::Random::MT::Auto   PACKAGE = Math::Random::MT::Auto
PROTOTYPES: DISABLE

BOOT:
{
    MY_CXT_INIT;
}

Math::Random::MT::Auto::_PRNG_
SA_prng()
    PREINIT:
        dMY_CXT;
    CODE:
        /*** Returns a pointer to the standalone PRNG context ***/

        /* These initializations ensure that the standalone PRNG is 'safe' */
        MY_CXT.state[0]          = HI_BIT;
        MY_CXT.left              = 1;
        MY_CXT.gaussian.have     = 0;
        MY_CXT.gaussian.value    = 0.0;
        MY_CXT.poisson.mean      = -1;
        MY_CXT.poisson.log_mean  = 0.0;
        MY_CXT.poisson.sqrt2mean = 0.0;
        MY_CXT.poisson.term      = 0.0;
        MY_CXT.binomial.trials   = -1;
        MY_CXT.binomial.term     = 0.0;
        MY_CXT.binomial.prob     = -1.0;
        MY_CXT.binomial.plog     = 0.0;
        MY_CXT.binomial.pclog    = 0.0;

        RETVAL = &MY_CXT;
    OUTPUT:
        RETVAL

UV
mt_irand(...)
    PREINIT:
        dMY_CXT;
    CODE:
        /*** Returns a random integer for the standalone PRNG ***/
        RETVAL = NEXT_ELEM(MY_CXT);
        TEMPER_ELEM(RETVAL);
    OUTPUT:
        RETVAL

NV
mt_rand(...)
    PREINIT:
        dMY_CXT;
        UV rand;
    CODE:
        /*** Returns a random number for the standalone PRNG ***/

        /* Random number on [0,1) interval */
        rand = NEXT_ELEM(MY_CXT);
        TEMPER_ELEM(rand);
        RETVAL = RAND_0i_1x(rand);
        if (items >= 1) {
            /* Random number on [0,X) interval */
            RETVAL *= SvNV(ST(0));
        }
    OUTPUT:
        RETVAL

Math::Random::MT::Auto::_PRNG_
OO_prng()
    CODE:
        /*** Returns a pointer to a new PRNG context for the OO Interface ***/
        RETVAL = calloc(1, sizeof(my_cxt_t));
        RETVAL->poisson.mean    = -1;
        RETVAL->binomial.trials = -1;
        RETVAL->binomial.prob   = -1.0;
    OUTPUT:
        RETVAL

UV
irand(rand_obj)
        HV *rand_obj
    PREINIT:
        IV tmp;
        my_cxt_t *prng;
    CODE:
        /*** Returns a random integer for a PRNG object ***/

        /* Extract PRNG context from object */
        /* prng = */ EXTRACT_PRNG(rand_obj);

        RETVAL = NEXT_ELEM_PTR(prng);
        TEMPER_ELEM(RETVAL);
    OUTPUT:
        RETVAL

NV
rand(rand_obj, ...)
        HV *rand_obj
    PREINIT:
        IV tmp;
        my_cxt_t *prng;
        UV rand;
    CODE:
        /*** Returns a random number for a PRNG object ***/

        /* Extract PRNG context from object */
        /* prng = */ EXTRACT_PRNG(rand_obj);

        /* Random number on [0,1) interval */
        rand = NEXT_ELEM_PTR(prng);
        TEMPER_ELEM(rand);
        RETVAL = RAND_0i_1x(rand);
        if (items >= 2) {
            /* Random number on [0,X) interval */
            RETVAL *= SvNV(ST(1));
        }
    OUTPUT:
        RETVAL

void
OO_DESTROY(prng)
        Math::Random::MT::Auto::_PRNG_ prng
    PREINIT:
        dMY_CXT;
    CODE:
        /*** Object cleanup ***/
        if (prng && (prng != &MY_CXT)) {
            free(prng);
        }

void
X_seed(prng, seed)
        Math::Random::MT::Auto::_PRNG_ prng
        AV *seed
    PREINIT:
        int ii, jj, kk;
        int len;
        UV *st;
    CODE:
        /*** Seeds a PRNG ***/

        len = av_len(seed)+1;
        st = prng->state;

        /* Initialize */
        st[0]= 19650218;
        for (ii=1; ii<N; ii++) {
            st[ii] = (MAGIC1 * (st[ii-1] ^ (st[ii-1] >> BIT_SHIFT)) + ii);
        }

        /* Add supplied seed */
        ii=1; jj=0;
        for (kk = ((N>len) ? N : len); kk; kk--) {
            st[ii] = (st[ii] ^ ((st[ii-1] ^ (st[ii-1] >> BIT_SHIFT)) * MAGIC2))
                            + SvUV(*av_fetch(seed, jj, 0)) + jj;
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
        prng->left = 1;

SV *
X_get_state(prng)
        Math::Random::MT::Auto::_PRNG_ prng
    PREINIT:
        int ii;
        AV *state;
    CODE:
        /*** Returns array ref containing PRNG state vector ***/
        state = newAV();
        for (ii=0; ii<N; ii++) {
            av_push(state, newSVuv(prng->state[ii]));
        }
        av_push(state, newSViv(prng->left));
        av_push(state, newSViv(prng->gaussian.have));
        av_push(state, newSVnv(prng->gaussian.value));
        av_push(state, newSVnv(prng->poisson.mean));
        av_push(state, newSVnv(prng->poisson.log_mean));
        av_push(state, newSVnv(prng->poisson.sqrt2mean));
        av_push(state, newSVnv(prng->poisson.term));
        av_push(state, newSViv(prng->binomial.trials));
        av_push(state, newSVnv(prng->binomial.term));
        av_push(state, newSVnv(prng->binomial.prob));
        av_push(state, newSVnv(prng->binomial.plog));
        av_push(state, newSVnv(prng->binomial.pclog));
        RETVAL = newRV_noinc((SV *)state);
    OUTPUT:
        RETVAL

void
X_set_state(prng, state)
        Math::Random::MT::Auto::_PRNG_ prng
        AV *state
    PREINIT:
        int ii;
    CODE:
        /*** Sets PRNG state vector from input array ref ***/
        for (ii=0; ii<N; ii++) {
            prng->state[ii] = SvUV(*av_fetch(state, ii, 0));
        }
        prng->left = SvIV(*av_fetch(state, ii, 0)); ii++;
        if (prng->left > 1) {
            prng->next = &prng->state[(N+1) - prng->left];
        }
        prng->gaussian.have     = SvIV(*av_fetch(state, ii, 0)); ii++;
        prng->gaussian.value    = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->poisson.mean      = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->poisson.log_mean  = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->poisson.sqrt2mean = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->poisson.term      = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->binomial.trials   = SvIV(*av_fetch(state, ii, 0)); ii++;
        prng->binomial.term     = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->binomial.prob     = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->binomial.plog     = SvNV(*av_fetch(state, ii, 0)); ii++;
        prng->binomial.pclog    = SvNV(*av_fetch(state, ii, 0));

SV *
shuffle(...)
    PREINIT:
        PRNG_VARS;
        AV *ary;
        I32 ii, jj;
        UV rand;
        SV *elem;
    CODE:
        PRNG_PREP;

        /*** Shuffles input data using the Fisher-Yates shuffle algorithm ***/

        /* Handle arguments */
        if (items == 1 && SvROK(ST(idx)) && SvTYPE(SvRV(ST(idx)))==SVt_PVAV) {
            /* User supplied array reference */
            ary = (AV*)SvRV(ST(idx));
            RETVAL = newRV_inc((SV *)ary);

        } else {
            /* Create an array from user supplied values */
            ary = newAV();
            while (items--) {
                av_push(ary, newSVsv(ST(idx++)));
            }
            RETVAL = newRV_noinc((SV *)ary);
        }

        /* Process elements from last to second */
        for (ii=av_len(ary); ii > 0; ii--) {
            /* Pick a random element from the beginning
               of the array to the current element */
            rand = NEXT_ELEM_PTR(prng);
            TEMPER_ELEM(rand);
            jj = rand % (ii + 1);
            /* Swap elements */
            elem = AvARRAY(ary)[ii];
            AvARRAY(ary)[ii] = AvARRAY(ary)[jj];
            AvARRAY(ary)[jj] = elem;
        }
    OUTPUT:
        RETVAL

NV
gaussian(...)
    PREINIT:
        PRNG_VARS;
        UV u1, u2;
        NV v1, v2, r, factor;
    CODE:
        PRNG_PREP;

        /*** Returns random number from a Gaussian distribution ***/

        if (prng->gaussian.have) {
            /* Use number generated during previous call */
            prng->gaussian.have = 0;
            RETVAL = prng->gaussian.value;

        } else {
            /* Marsaglia's polar method for the Box-Muller transformation */
            /* See 'Numerical Recipes in C', Chapter 7.2 */
            do {
                u1 = NEXT_ELEM_PTR(prng);
                u2 = NEXT_ELEM_PTR(prng);
                TEMPER_ELEM(u1);
                TEMPER_ELEM(u2);
                v1 = RAND_NEG1x_1x(u1);
                v2 = RAND_NEG1x_1x(u2);
                r = v1*v1 + v2*v2;
            } while (r >= 1.0 || r == 0.0);

            factor = sqrt((-2.0 * log(r)) / r);
            RETVAL = v1 * factor;

            /* Save 2nd value for later */
            prng->gaussian.have = 1;
            prng->gaussian.value = v2 * factor;
        }

        if (items) {
            /* Gaussian distribution with SD = X */
            RETVAL *= SvNV(ST(idx));
            if (items > 1) {
                /* Gaussian distribution with mean = Y */
                RETVAL += SvNV(ST(idx+1));
            }
        }
    OUTPUT:
        RETVAL

NV
exponential(...)
    PREINIT:
        PRNG_VARS;
    CODE:
        PRNG_PREP;

        /*** Returns random number from an exponential distribution ***/

        /* Exponential distribution with mean = 1 */
        RETVAL = -log(_rand(prng));
        if (items) {
            /* Exponential distribution with mean = X */
            RETVAL *= SvNV(ST(idx));
        }
    OUTPUT:
        RETVAL

NV
erlang(...)
    PREINIT:
        PRNG_VARS;
        IV order;
        IV ii;
        NV am, ss, tang, bound;
        UV ytmp;
    CODE:
        PRNG_PREP;

        /*** Returns random number from an Erlang distribution ***/

        /* Check argument */
        if (! items) {
            Perl_croak(aTHX_ "Missing argument to erlang()");
        }
        if ((order = SvIV(ST(idx))) < 1) {
            Perl_croak(aTHX_ "Bad argument (< 1) to erlang()");
        }

        if (order < 6) {
            /* Direct method of 'adding exponential randoms' */
            RETVAL = 1.0;
            for (ii=0; ii < order; ii++) {
                RETVAL *= _rand(prng);
            }
            RETVAL = -log(RETVAL);

        } else {
            /* Use J. H. Ahren's rejection method */
            /* See 'Numerical Recipes in C', Chapter 7.3 */
            am = order - 1;
            ss = sqrt(2.0 * am + 1.0);
            do {
                do {
                    tang = tan(PI * _rand(prng));
                    RETVAL = (tang * ss) + am;
                } while (RETVAL <= 0.0);
                bound = ((tang*tang) + 1.0) * exp(am * log(RETVAL/am) - ss*tang);
            } while (_rand(prng) > bound);
        }

        if (items > 1) {
            /* Erlang distribution with mean = X */
            RETVAL *= SvNV(ST(idx+1));
        }
    OUTPUT:
        RETVAL

IV
poisson(...)
    PREINIT:
        PRNG_VARS;
        NV mean;
        NV em, tang, bound, limit;
    CODE:
        PRNG_PREP;

        /*** Returns random number from a Poisson distribution ***/

        /* Check argument(s) */
        if (! items) {
            Perl_croak(aTHX_ "Missing argument(s) to poisson()");
        }
        if (items == 1) {
            if ((mean = SvNV(ST(idx))) <= 0.0) {
                Perl_croak(aTHX_ "Bad argument (<= 0) to poisson()");
            }
        } else {
            if ((mean = SvNV(ST(idx)) * SvNV(ST(idx+1))) < 1.0) {
                Perl_croak(aTHX_ "Bad arguments (rate*time <= 0) to poisson()");
            }
        }

        if (mean < 12.0) {
            /* Direct method */
            bound = 1.0;
            limit = exp(-mean);
            for (RETVAL=0; ; RETVAL++) {
                bound *= _rand(prng);
                if (bound < limit) {
                    break;
                }
            }

        } else {
            /* Rejection method */
            /* See 'Numerical Recipes in C', Chapter 7.3 */
            if (prng->poisson.mean != mean) {
                prng->poisson.mean      = mean;
                prng->poisson.log_mean  = log(mean);
                prng->poisson.sqrt2mean = sqrt(2.0 * mean);
                prng->poisson.term      = (mean * prng->poisson.log_mean)
                                                - _ln_gamma(mean + 1.0);
            }
            do {
                do {
                    tang = tan(PI * _rand(prng));
                    em = (tang * prng->poisson.sqrt2mean) + mean;
                } while (em < 0.0);
                em = floor(em);
                bound = 0.9 * ((tang*tang) + 1.0)
                            * exp((em * prng->poisson.log_mean)
                                        - _ln_gamma(em+1.0)
                                        - prng->poisson.term);
            } while (_rand(prng) > bound);
            RETVAL = (int)em;
        }
    OUTPUT:
        RETVAL

IV
binomial(...)
    PREINIT:
        PRNG_VARS;
        NV prob;
        IV trials;
        int ii;
        NV p, pc, mean;
        NV en, em, tang, bound, limit, sq;
    CODE:
        PRNG_PREP;

        /*** Returns random number from a binomial distribution ***/

        /* Check argument(s) */
        if (items < 2) {
            Perl_croak(aTHX_ "Missing argument(s) to binomial()");
        }
        if (((prob = SvNV(ST(idx))) < 0.0 || prob > 1.0) ||
            ((trials = SvIV(ST(idx+1))) < 0))
        {
            Perl_croak(aTHX_ "Invalid argument(s) to binomial()");
        }

        /* If probability > .5, then calculate based on non-occurance */
        p = (prob <= 0.5) ? prob : 1.0-prob;

        if (trials < 25) {
            /* Direct method */
            RETVAL = 0;
            for (ii=1; ii <= trials; ii++) {
                if (_rand(prng) < p) {
                    RETVAL++;
                }
            }

        } else {
            if ((mean = p * trials) < 1.0) {
                /* Use direct Poisson method */
                bound = 1.0;
                limit = exp(-mean);
                for (RETVAL=0; RETVAL < trials; RETVAL++) {
                    bound *= _rand(prng);
                    if (bound < limit) {
                        break;
                    }
                }

            } else {
                /* Rejection method */
                /* See 'Numerical Recipes in C', Chapter 7.3 */
                en = (NV)trials;
                pc = 1.0 - p;
                sq = sqrt(2.0 * mean * pc);

                if (trials != prng->binomial.trials) {
                    prng->binomial.trials = trials;
                    prng->binomial.term = _ln_gamma(en + 1.0);
                }
                if (p != prng->binomial.prob) {
                    prng->binomial.prob  = p;
                    prng->binomial.plog  = log(p);
                    prng->binomial.pclog = log(pc);
                }

                do {
                    do {
                        tang = tan(PI * _rand(prng));
                        em = (sq * tang) + mean;
                    } while (em < 0.0 || em >= (en+1.0));
                    em = floor(em);
                    bound = 1.2 * sq * (1.0+tang*tang) *
                                exp(prng->binomial.term -
                                    _ln_gamma(em + 1.0) -
                                    _ln_gamma(en - em + 1.0) +
                                    em * prng->binomial.plog +
                                    (en - em) * prng->binomial.pclog);
                } while (_rand(prng) > bound);
                RETVAL = (IV)em;
            }
        }

        /* Adjust results for occurance vs. non-occurance */
        if (p < prob) {
            RETVAL = trials - RETVAL;
        }

    OUTPUT:
        RETVAL
