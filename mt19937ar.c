/*
   A C-program for MT19937, with initialization improved 2002/1/26.
   Coded by Takuji Nishimura and Makoto Matsumoto, and including
   Shawn Cokus's optimizations.

   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.
   Copyright (C) 2005, Mutsuo Saito,
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

#include "mt19937ar.h"

/* Initializes based on supplied array of seed values */
void
mt_seed(struct mt *self, uint32_t seed[], int seed_len)
{
    uint32_t *st = self->state;
    int ii, jj, kk;

    /* Initialize */
    st[0]= 19650218;
    for (ii=1; ii<N; ii++) {
        st[ii] = (1812433253 * (st[ii-1] ^ (st[ii-1] >> 30)) + ii);
    }

    /* Add supplied seed */
    ii=1; jj=0;
    for (kk = ((N>seed_len) ? N : seed_len); kk; kk--) {
        st[ii] = (st[ii] ^ ((st[ii-1] ^ (st[ii-1] >> 30)) * 1664525)) + seed[jj] + jj;
        if (++ii >= N) { st[0] = st[N-1]; ii=1; }
        if (++jj >= seed_len) jj=0;
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


#define MIXBITS(u,v) ( ((u) & 0x80000000) | ((v) & 0x7fffffff) )
#define TWIST(u,v) ((MIXBITS(u,v) >> 1) ^ ((v)&1UL ? 0x9908b0df : 0UL))

/* The guts of the algorithm */
uint32_t
_mersenne(struct mt *self)
{
    uint32_t *st = self->state;
    uint32_t *sn = &st[2];
    uint32_t *sx = &st[M];
    uint32_t n0 = st[0];
    uint32_t n1 = st[1];
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


/* Generates a random number on [0,0xffffffff]-interval */
uint32_t
mt_rand32(struct mt *self)
{
    uint32_t rand = (--self->left == 0)
                            ? _mersenne(self)
                            : *self->next++;
    rand ^= (rand >> 11);
    rand ^= (rand << 7)  & 0x9d2c5680;
    rand ^= (rand << 15) & 0xefc60000;
    return (rand ^ (rand >> 18));
}

/* EOF */
