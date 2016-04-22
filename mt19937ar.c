/*
   A C-program for MT19937, with initialization improved 2002/1/26.
   Coded by Takuji Nishimura and Makoto Matsumoto.

   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.
   Copyright (C) 2005, Mutsuo Saito,
   All rights reserved.

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
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

   Any feedback is very welcome.
   http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html
   email: m-mat @ math.sci.hiroshima-u.ac.jp (remove space)

   Adaptations by:

   Copyright 2001 Abhijit Menon-Sen. All rights reserved.

   This software is distributed under the terms of the Artistic License
   http://ams.wiw.org/code/artistic.txt

   Copyright 2005 Jerry D. Hedden <jdhedden@1979.usna.com>
*/

#include "mt19937ar.h"

/* Allocates memory and initializes based on supplied array of seed values */
struct mt *genrand_init_by_array(uint32_t init_key[], int key_length)
{
    struct mt *self = malloc(sizeof(struct mt));
    uint32_t *mt;
    int ii, jj, kk;

    if (self) {
        mt = self->mt;

        mt[0]= 19650218;
        for (ii=1; ii<N; ii++) {
            mt[ii] = (1812433253 * (mt[ii-1] ^ (mt[ii-1] >> 30)) + ii);
        }
        self->mti = N;

        ii=1; jj=0;
        kk = (N>key_length ? N : key_length);
        for (; kk; kk--) {
            mt[ii] = (mt[ii] ^ ((mt[ii-1] ^ (mt[ii-1] >> 30)) * 1664525)) + init_key[jj] + jj;
            ii++; jj++;
            if (ii>=N) { mt[0] = mt[N-1]; ii=1; }
            if (jj>=key_length) jj=0;
        }
        for (kk=N-1; kk; kk--) {
            mt[ii] = (mt[ii] ^ ((mt[ii-1] ^ (mt[ii-1] >> 30)) * 1566083941)) - ii;
            ii++;
            if (ii>=N) { mt[0] = mt[N-1]; ii=1; }
        }

        mt[0] = 0x80000000;
    }

    return (self);
}

/* Generates a random number on [0,0xffffffff]-interval */
uint32_t genrand_rand32(struct mt *self)
{
    uint32_t *mt = self->mt;
    uint32_t y;
    static const uint32_t mag01[2]={0, 0x9908b0df};

    if (self->mti >= N) {
        int kk;

        for (kk=0;kk<N-M;kk++) {
            y = (mt[kk]&0x80000000)|(mt[kk+1]&0x7fffffff);
            mt[kk] = mt[kk+M] ^ (y >> 1) ^ mag01[y & 1];
        }
        for (;kk<N-1;kk++) {
            y = (mt[kk]&0x80000000)|(mt[kk+1]&0x7fffffff);
            mt[kk] = mt[kk+(M-N)] ^ (y >> 1) ^ mag01[y & 1];
        }
        y = (mt[N-1]&0x80000000)|(mt[0]&0x7fffffff);
        mt[N-1] = mt[M-1] ^ (y >> 1) ^ mag01[y & 1];

        self->mti = 0;
    }

    y = mt[self->mti++];

    y ^= (y >> 11);
    y ^= (y << 7)  & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= (y >> 18);

    return y;
}

/* Free up memory */
void genrand_free(struct mt *self)
{
    if (self) {
        free(self);
    }
}

/* EOF */
