package Math::Random::MT::Auto;

use strict;
use warnings;

use Scalar::Util 'looks_like_number';

require DynaLoader;
our @ISA = qw(DynaLoader);

our $VERSION = 1.00;

bootstrap Math::Random::MT::Auto $VERSION;

# Default seeding methods
my @seeders = qw/dev_random random_org hotbits dev_urandom/;

# Auto-seed the PRNG via an INIT block
my $auto_seed = 1;

# Last seed sent to the PRNG
our @seed;

# For storing error messages
our @errors;


# Handles importation of random functions,
#   and specification of seeding methods
sub import
{
    my $pkg = caller;
    no strict 'refs';

    my @methods;

    while (my $sym = shift(@_)) {
        # Exportable functions
        if ($sym eq 'rand32' ||
            $sym eq 'rand'   ||
            $sym eq 'srand'  ||
            $sym eq 'seed')
        {
            *{"${pkg}::$sym"} = \&$sym;

        } elsif ($sym =~ 'auto') {
            # To auto-seed or not
            $auto_seed = $sym =~ /no|!/;

        } elsif ($sym eq 'dev_random'  ||
                 $sym eq 'dev_urandom' ||
                 $sym eq 'random_org'  ||
                 $sym eq 'hotbits')
        {
            # User-specified seed acquisition methods
            push(@methods, $sym);
            if (@_ && looks_like_number($_[0])) {
                push(@methods, shift(@_));
            }
        }
    }

    # Save user-specified seed acquisition methods
    if (@methods) {
        @seeders = @methods;
    }
}


# Auto seed the PRNG when module is loaded
# Even when $auto_seed is false, the PRNG is still seeded using time and PID
INIT {
    Math::Random::MT::Auto::_seed(($auto_seed) ? @seeders : 'none');
}


# Starts PRNG with random seed using specified methods (if any)
sub srand
{
    # Save specified methods, if any
    if (@_) {
        @seeders = @_;
    }

    # Seed the PRNG
    _seed(@seeders);
}


# Seeds the PRNG (internal subroutine)
sub _seed
{
    my @methods = @_;

    undef(@seed);

    for (my $ii=0; $ii < @methods; $ii++) {
        my $method = $methods[$ii];

        my $need = 624 - @seed;
        if (($ii+1 < @methods) && looks_like_number($methods[$ii+1])) {
            if ($methods[++$ii] < $need) {
                $need = $methods[$ii];
            }
        }
        my $bytes  = 4 * $need;

        if ($method eq 'dev_random') {
            # Try reading from /dev/random
            my $FH;
            if (! open($FH, '/dev/random')) {
                push(@errors, "Failure opening /dev/random: $!");
                next;
            }
            binmode($FH);
            # Set non-blocking mode
            eval { use Fcntl; };
            if ($@) {
                close($FH);
                push(@errors, "Failure importing Fcntl module: $@");
                next;
            }
            my $flags = 0;
            if (! fcntl($FH, F_GETFL, $flags)) {
                push(@errors, "Failure getting filehandle flags: $!");
                close($FH);
                next;
            }
            $flags |= O_NONBLOCK;
            if (! fcntl($FH, F_SETFL, $flags)) {
                push(@errors, "Failure setting filehandle flags: $!");
                close($FH);
                next;
            }
            # Read data
            my $seed;
            my $cnt = read($FH, $seed, $bytes);
            close($FH);
            if (defined($cnt)) {
                if ($cnt < $bytes) {
                    push(@errors, "/dev/random exhausted");
                }
                if ($cnt = int($cnt/4)) {
                    push(@seed, unpack("L$cnt", $seed));
                }
            } else {
                push(@errors, "Failure reading from /dev/random: $!");
            }

        } elsif ($method eq 'dev_urandom') {
            # Try reading from /dev/urandom
            my $FH;
            if (! open($FH, '/dev/urandom')) {
                push(@errors, "Failure opening /dev/urandom: $!");
                next;
            }
            binmode($FH);
            # Read data
            my $seed;
            my $cnt = read($FH, $seed, $bytes);
            close($FH);
            if (defined($cnt)) {
                if ($cnt = int($cnt/4)) {
                    push(@seed, unpack("L$cnt", $seed));
                }
            } else {
                push(@errors, "Failure reading from /dev/urandom: $!");
            }

        } elsif ($method eq 'random_org') {
            # Get data from random.org
            eval { require LWP::UserAgent; };
            if ($@) {
                push(@errors, "Failure importing LWP::UserAgent: $@");
                next;
            }
            my $res;
            eval {
                # Create user agent
                my $ua = LWP::UserAgent->new( timeout => 10, env_proxy => 1 );
                # Create request to random.org
                my $req = HTTP::Request->new(GET =>
                        "http://www.random.org/cgi-bin/randbyte?nbytes=$bytes");
                # Get the seed
                $res = $ua->request($req);
            };
            if ($@) {
                push(@errors, "Failure contacting random.org: $@");
            }
            if ($res->is_success) {
                push(@seed, unpack("L$need", $res->content));
            } else {
                push(@errors, 'Failure getting data from random.org: '
                                    . $res->status_line);
            }

        } elsif ($method eq 'hotbits') {
            # Get data from random.org
            eval { require LWP::UserAgent; };
            if ($@) {
                push(@errors, "Failure importing LWP::UserAgent: $@");
                next;
            }
            my $res;
            eval {
                # Create user agent
                my $ua = LWP::UserAgent->new( timeout => 10, env_proxy => 1 );
                # Hotbit only allows 2048 bytes max.
                if ($bytes > 2048) {
                    $bytes = 2048;
                    $need  = 512;
                }
                # Create request for Hotbits
                my $req = HTTP::Request->new(GET =>
                        "http://www.fourmilab.ch/cgi-bin/uncgi/Hotbits?fmt=bin&nbytes=$bytes");
                # Get the seed
                $res = $ua->request($req);
            };
            if ($@) {
                push(@errors, "Failure contacting HotBits: $@");
            }
            if ($res->is_success) {
                if ($res->content =~ /exceeded your 24-hour quota/) {
                    push(@errors, $res->content);
                } else {
                    push(@seed, unpack("L$need", $res->content));
                }
            } else {
                push(@errors, 'Failure getting data from HotBits: '
                                    . $res->status_line);
            }
        }

        # Check if done
        if (@seed >= 624) {
            last;
        }
    }

    # If still needed, make use of time and PID
    if (@seed < 624) {
        if ($methods[0] ne 'none') {
            push(@errors, 'Full seed not acquired from sources: ' . scalar(@seed));
        }
        push(@seed, time());
        if (@seed < 624) {
            push(@seed, $$);
        }
    }

    # Seed the PRNG
    Math::Random::MT::Auto::seed(@seed);
}

1;

__END__

=head1 NAME

Math::Random::MT::Auto - Auto-seeded Mersenne Twister PRNG

=head1 SYNOPSIS

  use Math::Random::MT::Auto qw/rand32 rand/,
                             'dev_random' => 500,
                             'random_org';

  my $die_roll = int(rand(6)) + 1;

  my $coin_flip = (rand32() & 1) ? 'heads' : 'tails';

=head1 DESCRIPTION

This module provides a two random number functions that are based on the
Mersenne Twister pseudorandom number generator (PRNG).

The PRNG is self-seeding, automatically acquiring a 624-long-int random
seed when the module is loaded.

=head2 Seeding Methods

=over

=item dev_random

This reads random data from F</dev/random> (if it exists).  There is a (very
slight) possibility that there may not be sufficient data available from
this device.

=item dev_urandom

This reads random data from F</dev/urandom> (if it exists).  This device
provides data first from F</dev/random>, and then if needed, will satisfy
the rest of the request using data from its own PRNG.

=item random_org

This reads random data from the random.org web site.  An Internet
connection and L<LWP::UserAgent> are required to utilize this source.

If you connect to the Internet through an HTTP proxy, then you must set
the C<http_proxy> variable in your environment when using this source.
(See L<LWP::UserAgent/"Proxy attributes">.)

=item hotbits

This reads random data from the HotBits web site.  An Internet connection
and L<LWP::UserAgent> are required to utilize this source.

If you connect to the Internet through an HTTP proxy, then you must set
the C<http_proxy> variable in your environment when using this source.
(See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site will only provide a maximum of 512 long-ints of data per
request.  If you want to get the full seed from HotBits, then specify
the C<hotbits> method twice in the module declaration.

=head3 Example

  use Math::Random::MT::Auto qw/hotbits hotbits dev_urandom/;

=back

Seeding methods may be specified when the module is declared.  Optionally,
the maximum number of long-ints to be used from that source may be
specified.

Seeding methods may also be specified though the C<srand> function if
reseeding of the PRNG is desired.

=head3 Example

  use Math::Random::MT::Auto 'random_org' => 500, 'dev_urandom';

This acquires at most 500 long-ints from random.org, and then finishes the
rest of the seed using data from F</dev/urandom>.

  use Math::Random::MT::Auto qw/dev_random random_org hotbits dev_urandom/;

This acquires the seed from the sources specified, in order, until the full
seed is acquired.  (This is the default.)

=head2 Auto-seeding

Normally, the PRNG is seeded in a C<INIT> block that is run right after the
module is loaded.  This behavior can be modified by supplying the C<:!auto>
(or C<:noauto>) flag when the module is declared.  (Even in this case, the
PRNG will still be seeded using time and PID.)  When the C<:!auto> option is
used, the C<srand> function should be imported and then run before using
C<rand> or C<rand32>.

=head3 Example

  use Math::Random::MT::Auto qw/rand srand :!auto/;
    ...
  srand();
    ...
  my $rn = rand(5);

=head2 Functions

=over

=item rand($num)

Behaves exactly like Perl's builtin C<rand>, returning a number uniformly
distributed in [0, $num) ($num defaults to 1).

=item rand32()

Returns a 32-bit random integer between 0 and 2^32-1 inclusive.

=item srand()

This reseeds the PRNG.  It should be called when the C<:!auto> option is
used.

Optionally, seed aquisition methods may be supplied as arguments.  (These
will be saved and used again if C<srand> is subsequently called without
arguments).

=over

=item Example

  srand('dev_random');

This will attempt to fill the seed with data from F</dev/random> only.

=back

=item seed(@seeds)

This will seed the PRNG with the supplied values.  This can be used to
set up the PRNG with a pre-determined seed, or to make use of some other
source of random seed data.  (I would be interested to hear about such
sources if they could easily be included in future versions of this
module.)

=back

=head2 Module Data

=over

=item @Math::Random::MT::Auto::seed

This array contains the seed that was last used to intialize the PRNG.  It
may be of use in setting up repeatable sequences of random numbers.

=item @Math::Random::MT::Auto::errors

This array contains information related to any problem encountered while
trying to acquire seed data.  It can be examined after the module is loaded,
or after C<srand> is called when C<:!auto> is used.

=back

=head1 DIAGNOSTICS

If you connect to the Internet through an HTTP proxy, then you must set the
C<http_proxy> variable in your environment when using the Internet seed
sources.  (See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site has a quota on the amount of data you can request in a
24-hour period.  (I don't know how big the quota is.)  Therefore, this
source may fail to provide any data if used too often.

If the module cannot acquire a full seed from the specified sources, then
the time() and PID will be added to whatever seed data is acquired so far.

=head1 PERFORMANCE

This module is 50% faster than Math::Random::MT.  The file F<samples/random>
included with this module can be used to compare timing results.

Depending on your connnection speed, acquiring seed data from the Internet
may take a couple of seconds.  This delay might be apparent when your
application is first started.  This is especially true if you specify the
C<hotbits> method twice so as to get the full seed from the HotBits site as
this results in two accesses to the Internet.  (If F</dev/random> is
available on your machine, then you should definitely consider using the
Internet sources only as a secondary source.)

=head1 SEE ALSO

The Mersenne Twister is the (current) quintessential pseudorandom number
generator. It is fast, and has a period of 2^19937 - 1 (> 10^6000).  The
Mersenne Twister algorithm was developed by Makoto Matsumoto and Takuji
Nishimura.
L<http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>

random.org generates random numbers from radio frequency noise.
L<http://random.org/>

HotBits generates random number from a radioactive decay source.
L<http://www.fourmilab.ch/hotbits/>

Man pages for F</dev/random> and F</dev/urandom>.
L<http://www.die.net/doc/linux/man/man4/random.4.html>

L<LWP::UserAgent>

L<Math::Random::MT>

L<Random::Net>

=head1 AUTHOR

Jerry D. Hedden, S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

=head1 COPYRIGHT AND LICENSE

A C-program for MT19937, with initialization improved 2002/1/26.
Coded by Takuji Nishimura and Makoto Matsumoto, and including
Shawn Cokus's optimizations.

Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
All rights reserved.
Copyright (C) 2005, Mutsuo Saito,
All rights reserved.
Copyright 2005 Jerry D. Hedden S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

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
S<E<lt>m-mat AT math DOT sci DOT hiroshima-u DOT ac DOT jpE<gt>>
L<http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>

=cut
