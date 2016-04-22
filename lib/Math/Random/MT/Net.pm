package Math::Random::MT::Net;

use strict;
use warnings;

require Exporter;
use DynaLoader;
our @ISA = qw(Exporter DynaLoader);
our @EXPORT = qw(rand32 rand);

our $VERSION = 1.00;

use LWP::UserAgent;

bootstrap Math::Random::MT::Net $VERSION;


### Package Globals ###

my $prng;   # The PRNG object


### Package Constants ###

# URL for getting random seed from random.org
my $RAND_URL = 'http://www.random.org/cgi-bin/randbyte?nbytes=2496';

# Set a reasonable response time for random.org
my $TIMEOUT = 10;


### Exported Package Functions ###

# Quickest random number function
sub rand32
{
    # Check if seeded
    if (! $prng) {
        _srand();
    }

    return (Math::Random::MT::Net::mt_rand32($prng));
}


# Just like the Perl builtin
sub rand
{
    # Check if seeded
    if (! $prng) {
        _srand();
    }

    my $rn = Math::Random::MT::Net::mt_rand32($prng) / 4294967296.0;

    return ((@_) ? $_[0] * $rn : $rn);
}


### Internal Package Subroutines ###

# Starts PRNG with random seed
sub _srand
{
    # Create user agent
    my $ua = LWP::UserAgent->new( timeout => $TIMEOUT, env_proxy => 1 );

    # Create request to random.org
    my $req = HTTP::Request->new(GET => $RAND_URL);

    # Get the seed
    my $res = $ua->request($req);

    if ($res->is_success) {
        # Set up PRNG with seed
        $prng = Math::Random::MT::Net::mt_init(unpack('L624', $res->content));
    } else {
        # Failure getting seed, so just seed the PRNG using time and PID.
        $prng = Math::Random::MT::Net::mt_init(time(), $$);
        # Issue a warning
        warn('WARNING: Math::Random::MT:Net couldn\'t get seed from random.org: '
                        . $res->status_line . "\n");
    }
    if (! $prng) {
        die("ERROR: Math::Random::MT:Net failed to initialize\n");
    }
}

sub DESTROY
{
    if ($prng) {
        Math::Random::MT::Net::mt_DESTROY($prng);
    }
}

1;

__END__

=head1 NAME

Math::Random::MT::Net - Auto-seeded Mersenne Twister PRNG

=head1 SYNOPSIS

  use Math::Random::MT::Net;

  my $rand_int = rand32();

  # Or use rand() as usual.

=head1 DESCRIPTION

This module provides a two random number functions that are based on the
Mersenne Twister pseudorandom number generator (PRNG).

The PRNG is self-seeding, automatically acquiring a 624-long-int random
seed from random.org the first time any of this module's functions are
called.

=head2 Functions

=over

=item rand($num)

Behaves exactly like Perl's builtin rand(), returning a number uniformly
distributed in [0, $num) ($num defaults to 1).

=item rand32()

Returns a 32-bit random integer between 0 and 2^32-1.  (This function is
faster than rand().)

=back

=head1 DIAGNOSTICS

The first time rand or rand32 is called, this module connects to
random.org to acquire a seed for the PRNG.  This may take a couple of
seconds.

If the module cannot connect to random.org, a 'warn'ing message will be
issued (trap it using a __WARN__ handler), and the PRNG will be seeded
using time() and PID.

If you connect to the web through an HTTP proxy, then you must set
the 'http_proxy' variable in your environment.  (See 'Proxy attributes'
in LWP::UserAgent.)

=head1 SEE ALSO

The Mersenne Twister is the (current) quintessential pseudorandom number
generator. It is fast, and has a period of 2^19937 - 1 (> 10^6000).
The Mersenne Twister algorithm was developed by Makoto Matsumoto and
Takuji Nishimura.
  http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html

random.org generates true random numbers from radio frequency noise.
  http://random.org/

LWP::UserAgent, Net::Random and Math::Random::MT

=head1 AUTHOR

Jerry D. Hedden, E<lt>jdhedden@1979.usna.comE<gt>

=head1 COPYRIGHT AND LICENSE

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

=cut
