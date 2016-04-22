/*
 * Math::Random::MT::Net
 * Copyright 2001 Abhijit Menon-Sen <ams@wiw.org>
 * Copyright 2005 Jerry D. Hedden <jdhedden@1979.usna.com>
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "mt19937ar.h"

typedef struct mt * Math__Random__MT__Net;

void * U32ArrayPtr ( int n ) {
    SV * sv = sv_2mortal( NEWSV( 0, n*sizeof(U32) ) );
    return SvPVX(sv);
}

MODULE = Math::Random::MT::Net   PACKAGE = Math::Random::MT::Net
PROTOTYPES: DISABLE

Math::Random::MT::Net
mt_init( array, ... )
    CODE:
        U32 * array = U32ArrayPtr( items );
        U32 ix_array = 0;
        while (items--) {
            array[ix_array] = (U32)SvIV(ST(ix_array));
            ix_array++;
        }
        RETVAL = genrand_init_by_array( (uint32_t*)array, ix_array );
    OUTPUT:
        RETVAL

U32
mt_rand32(self)
    Math::Random::MT::Net self
    CODE:
        RETVAL = genrand_rand32(self);
    OUTPUT:
        RETVAL

void
mt_DESTROY(self)
    Math::Random::MT::Net self
    CODE:
        genrand_free(self);
