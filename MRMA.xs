/*
   a c-Program for MT19937, with initialization improved 2002/1/26.
   Coded by Takuji Nishimura and Makoto Matsumoto, and including
   Shawn Cokus's optimizations.

   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.
   Copyright (C) 2005, Mutsuo Saito
   All rights reserved.
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

#define N 624
#define M 397

struct mt {
    U32 state[N];
    U32 *next;
    int left;
};

typedef struct mt my_cxt_t;
typedef struct mt *Math__Random__MT__Auto;

#define MIXBITS(u,v) ( ((u) & 0x80000000) | ((v) & 0x7FFFFFFF) )
#define TWIST(u,v) ((MIXBITS(u,v) >> 1) ^ ((v)&1UL ? 0x9908B0DF : 0UL))

/* The guts of the Mersenne Twister algorithm */
U32
_mt_algo(my_cxt_t *self)
{
    U32 *st = self->state;
    U32 *sn = &st[2];
    U32 *sx = &st[M];
    U32 n0 = st[0];
    U32 n1 = st[1];
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
void
_mt_seed(my_cxt_t *self, U32 *seed, int len)
{
    int ii, jj, kk;
    U32 *st = self->state;

    /* Initialize */
    st[0]= 19650218;
    for (ii=1; ii<N; ii++) {
        st[ii] = (1812433253 * (st[ii-1] ^ (st[ii-1] >> 30)) + ii);
    }

    /* Add supplied seed */
    ii=1; jj=0;
    for (kk = ((N>len) ? N : len); kk; kk--) {
        st[ii] = (st[ii] ^ ((st[ii-1] ^ (st[ii-1] >> 30)) * 1664525))
                        + seed[jj] + jj;
        if (++ii >= N) { st[0] = st[N-1]; ii=1; }
        if (++jj >= len) jj=0;
    }

    /* Final shuffle */
    for (kk=N-1; kk; kk--) {
        st[ii] = (st[ii] ^ ((st[ii-1] ^ (st[ii-1] >> 30)) * 1566083941)) - ii;
        if (++ii >= N) { st[0] = st[N-1]; ii=1; }
    }

    /* Guarantee non-zero initial state */
    st[0] = 0x80000000;

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
        MY_CXT.state[0] = 0x80000000;
        MY_CXT.left = 1;
        RETVAL = &MY_CXT;
    OUTPUT:
        RETVAL

U32
mt_rand32()
    PREINIT:
        dMY_CXT;
    CODE:
        /* Random number on [0,0xFFFFFFFF] interval */
        RETVAL = (--MY_CXT.left == 0) ? _mt_algo(&MY_CXT)
                                      : *MY_CXT.next++;
        RETVAL ^= (RETVAL >> 11);
        RETVAL ^= (RETVAL << 7)  & 0x9D2C5680;
        RETVAL ^= (RETVAL << 15) & 0xEFC60000;
        RETVAL ^= (RETVAL >> 18);
    OUTPUT:
        RETVAL

double
mt_rand(...)
    PREINIT:
        dMY_CXT;
    CODE:
        /* Random number on [0,1) interval */
        U32 rand = (--MY_CXT.left == 0) ? _mt_algo(&MY_CXT)
                                        : *MY_CXT.next++;
        rand ^= (rand >> 11);
        rand ^= (rand << 7)  & 0x9D2C5680;
        rand ^= (rand << 15) & 0xEFC60000;
        RETVAL = (double)(rand ^ (rand >> 18)) / 4294967296.0;
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

U32
rand32(rand_obj);
        HV *rand_obj
    INIT:
        /* Extract PRNG context from object */
        IV tmp = SvIV((SV*)SvRV(*hv_fetch(rand_obj, "PRNG", 4, 0)));
        my_cxt_t *prng = INT2PTR(my_cxt_t *, tmp);
    CODE:
        /* Random number on [0,0xFFFFFFFF] interval */
        RETVAL = (--prng->left == 0) ? _mt_algo(prng)
                                     : *prng->next++;
        RETVAL ^= (RETVAL >> 11);
        RETVAL ^= (RETVAL << 7)  & 0x9D2C5680;
        RETVAL ^= (RETVAL << 15) & 0xEFC60000;
        RETVAL ^= (RETVAL >> 18);
    OUTPUT:
        RETVAL

double
rand(rand_obj, ...);
        HV *rand_obj
    INIT:
        /* Extract PRNG context from object */
        IV tmp = SvIV((SV*)SvRV(*hv_fetch(rand_obj, "PRNG", 4, 0)));
        my_cxt_t *prng = INT2PTR(my_cxt_t *, tmp);
    CODE:
        /* Random number on [0,1) interval */
        U32 rand = (--prng->left == 0) ? _mt_algo(prng)
                                       : *prng->next++;
        rand ^= (rand >> 11);
        rand ^= (rand << 7)  & 0x9D2C5680;
        rand ^= (rand << 15) & 0xEFC60000;
        RETVAL = (double)(rand ^ (rand >> 18)) / 4294967296.0;
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
    CODE:
        /* Length of the seed */
        int len = av_len(seed)+1;
        /* Copy the seed */
        U32 *buff = (U32 *)malloc(len * sizeof(U32));
        int ii;
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
    CODE:
        /* Returns array ref containing PRNG state vector */
        AV *state = newAV();
        int ii;
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
    CODE:
        /* Sets PRNG state vector from input array ref */
        int ii;
        for (ii=0; ii<N; ii++) {
            prng->state[ii] = SvUV(*av_fetch(state, ii, 0));
        }
        prng->left = SvIV(*av_fetch(state, N, 0));
        if (prng->left > 1) {
            prng->next = &prng->state[(N+1) - prng->left];
        }
