package Math::Random::MT::Auto;

use strict;
use warnings;

use Scalar::Util 'looks_like_number';
use Carp;

require DynaLoader;
our @ISA = qw(DynaLoader);

our $VERSION = 1.10;

bootstrap Math::Random::MT::Auto $VERSION;

# Default seeding methods
my @seeders;

# Auto-seed the PRNG via an INIT block
my $auto_seed = 1;

# Last seed sent to the PRNG
my @seed;

# For storing error messages
our @errors;


# Handles importation of random functions,
#   and specification of seeding methods
sub import
{
    my $class = shift;
    my $pkg = caller;
    no strict 'refs';

    my @methods;

    while (my $sym = shift) {
        # Exportable functions
        if ($sym eq 'rand32' ||
            $sym eq 'rand'   ||
            $sym eq 'srand'  ||
            $sym eq 'seed'   ||
            $sym eq 'state')
        {
            *{"${pkg}::$sym"} = \&$sym;

        } elsif ($sym =~ 'auto') {
            # To auto-seed or not
            $auto_seed = $sym =~ /no|!/;

        } else {
            # User-specified seed acquisition methods
            # or user-defined seed acquisition functions
            push(@methods, $sym);
            # Max. count for method, if any
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


# Set up default seed sources
BEGIN {
    if (-e '/dev/urandom') {
        push(@seeders, '/dev/urandom');
    } elsif (-e '/dev/random') {
        push(@seeders, '/dev/random');
    }
    push(@seeders, 'random_org');
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


# Use supplied seed, if given
# Returns ref to saved seed
sub seed
{
    my $seed = $_[0];

    # User requested the seed
    if (! defined($seed)) {
        return (\@seed);
    }

    # Check input
    if (ref($seed) ne 'ARRAY') {
        croak('Arg to seed() not an array ref');
    }

    # Save a copy of the seed
    @seed = @{$seed};

    # Seed the PRNG
    Math::Random::MT::Auto::_seed_prng(\@seed);
}


# Set PRNG to supplied state, if given,
# or return copy of PRNG's current state
sub state
{
    my $state = $_[0];

    # User requested copy of state
    if (! defined($state)) {
        return (Math::Random::MT::Auto::_get_state());
    }

    # Set state of PRNG
    Math::Random::MT::Auto::_set_state($state);
}


### Internal Subroutines ###

# Seeds the PRNG
sub _seed
{
    my @methods = @_;

    @seed = ();

    for (my $ii=0; $ii < @methods; $ii++) {
        my $method = $methods[$ii];

        my $need = 624 - @seed;
        if (($ii+1 < @methods) && looks_like_number($methods[$ii+1])) {
            if ($methods[++$ii] < $need) {
                $need = $methods[$ii];
            }
        }

        if (ref($method) eq 'CODE') {
            # User supplied seeding function
            &$method(\@seed, $need);

        } elsif ($method =~ /[\/\\]/) {
            # Random device
            _seed_dev($method, \@seed, $need);

        } elsif ($method ne 'none') {
            # Module defined seeding method
            #   _seed_random_org, ...
            no strict 'refs';
            &{"_seed_$method"}(\@seed, $need);
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
        if (! @seed) {
            push(@seed, time(), $$);  # Default seed
        }
    }


    # Seed the PRNG
    Math::Random::MT::Auto::_seed_prng(\@seed);
}


sub _seed_dev
{
    my $device = $_[0];
    my $seed   = $_[1];
    my $need   = $_[2];
    my $bytes  = 4 * $need;

    # Try opening device
    my $FH;
    if (! open($FH, $device)) {
        push(@errors, "Failure opening $device $!");
        return;
    }
    binmode($FH);

    # Set non-blocking mode
    eval { use Fcntl; };
    if ($@) {
        close($FH);
        push(@errors, "Failure importing Fcntl module: $@");
        return;
    }
    my $flags = 0;
    if (! fcntl($FH, F_GETFL, $flags)) {
        push(@errors, "Failure getting filehandle flags: $!");
        close($FH);
        return;
    }
    $flags |= O_NONBLOCK;
    if (! fcntl($FH, F_SETFL, $flags)) {
        push(@errors, "Failure setting filehandle flags: $!");
        close($FH);
        return;
    }

    # Read data
    my $data;
    my $cnt = read($FH, $data, $bytes);
    close($FH);
    if (defined($cnt)) {
        if ($cnt < $bytes) {
            push(@errors, "$device exhausted");
        }
        if ($cnt = int($cnt/4)) {
            push(@$seed, unpack("L$cnt", $data));
        }
    } else {
        push(@errors, "Failure reading from $device: $!");
    }
}


sub _seed_random_org
{
    my $seed = $_[0];
    my $need = $_[1];
    my $bytes  = 4 * $need;

    # Get data from random.org
    eval { require LWP::UserAgent; };
    if ($@) {
        push(@errors, "Failure importing LWP::UserAgent: $@");
        return;
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
        push(@$seed, unpack("L$need", $res->content));
    } else {
        push(@errors, 'Failure getting data from random.org: '
                            . $res->status_line);
    }
}


sub _seed_hotbits
{
    my $seed = $_[0];
    my $need = $_[1];
    my $bytes  = 4 * $need;

    # Get data from random.org
    eval { require LWP::UserAgent; };
    if ($@) {
        push(@errors, "Failure importing LWP::UserAgent: $@");
        return;
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
            push(@$seed, unpack("L$need", $res->content));
        }
    } else {
        push(@errors, 'Failure getting data from HotBits: '
                            . $res->status_line);
    }
}

1;

__END__

=head1 NAME

Math::Random::MT::Auto - Auto-seeded Mersenne Twister PRNG

=head1 SYNOPSIS

  use Math::Random::MT::Auto qw/rand32 rand/,
                             '/dev/urandom' => 500,
                             'random_org';

  my $die_roll = int(rand(6)) + 1;

  my $coin_flip = (rand32() & 1) ? 'heads' : 'tails';

=head1 DESCRIPTION

This module provides two random number functions that are based on the
Mersenne Twister pseudorandom number generator (PRNG).

The PRNG is self-seeding, automatically acquiring a 624-long-int random
seed when the module is loaded.

=head2 Seeding Sources

=over

=item Random Devices

Most OSs offer some sort of device for acquiring random numbers.  The
most common are F</dev/urandom> and F</dev/random>.  You can specify the
use of these devices for acquiring the seed for the PRNG when you declare
this module:

  use Math::Random::MT::Auto '/dev/urandom';

or they can be specified when using the L</"srand"> function.

  srand('/dev/random');

The devices are accessed in I<non-blocking> mode so that if there is
insufficient data when they are read, the application will not hang waiting
for more.

=item File of Binary Data

Since the above devices are just files as far as Perl is concerned, you can
also use random data previously stored in files (in binary format).  (The
module looks for slashes or back-slashes to determine if the specified
source is a device or file, and not one of the Internet sources below.)

  srand('C:\\temp\\random.dat');

=item Internet Sites

This module provides support for acquiring seed data from two Internet
sites:  random.org and HotBits.  An Internet connection and
L<LWP::UserAgent> are required to utilize these sources.

  use Math::Random::MT::Auto 'random_org';
    # or
  use Math::Random::MT::Auto 'hotbits';

If you connect to the Internet through an HTTP proxy, then you must set
the C<http_proxy> variable in your environment when using this source.
(See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site will only provide a maximum of 512 long-ints of data per
request.  If you want to get the full seed from HotBits, then specify
the C<hotbits> source twice in the module declaration.

  use Math::Random::MT::Auto 'hotbits', 'hotbits' => 112;

=back

The default list of seeding sources is determined in a C<BEGIN> block
when the module is loaded.  First, F</dev/urandom> and then
F</dev/random> are checked.  The first one found is added to the list.
Then C<random_org> is added.

These defaults can be overriden by specifying the desired sources when
the module is declared, or through the use of the L</"srand"> function.

Optionally, the maximum number of long-ints to be used from a source
may be specified.

  # Get at most 500 long-ints from random.org, and then
  #  finishes the rest of the seed using data from /dev/urandom
  use Math::Random::MT::Auto 'random_org' => 500,
                             '/dev/urandom';

(I would be interested to hear about other random data sources if they
could easily be included in future versions of this module.)

=back

=head2 Auto-seeding

Normally, the PRNG is seeded in an C<INIT> block that is executed right
after the module is loaded.  This behavior can be modified by supplying the
C<:!auto> (or C<:noauto>) flag when the module is declared.  (Even in this
case, the PRNG will still be seeded using time and PID.)  When the
C<:!auto> option is used, the L</"srand"> function should be imported and
then run before calling L</"rand"> or L</"rand32">.

  use Math::Random::MT::Auto qw/rand srand :!auto/;
    ...
  srand();
    ...
  my $rn = rand(10);

=head2 Functions

By default, this module does not automatically export any of the functions
below.  If you want to use them without the full module-path, then you must
specify them when you declare the module.

  use Math::Random::MT::Auto qw/rand rand32 srand seed state/;

=over

=item rand($num)

Behaves exactly like Perl's builtin L<perlfunc/"rand">, returning a number
uniformly distributed in [0, $num) ($num defaults to 1).

=item rand32()

Returns a 32-bit random integer between 0 and 2^32-1 (0xFFFFFFFF) inclusive.

=item srand

This (re)seeds the PRNG.  It should definitely be called when the C<:!auto>
option is used.  Additionally, it may be called anytime reseeding of the
PRNG is desired (although this should normally not be needed).

When called without arguments, the previously determined/specified seeding
source(s) will be used to seed the PRNG.

Optionally, seeding sources may be supplied as arguments.  (These will be
saved and used again if L</"srand"> is subsequently called without
arguments).

  srand('hotbits', '/dev/random');

If called with a subroutine reference, then that subroutine will be called
to acquire the seeding data.  The subroutine will be passed two arguments:
A array reference where seed data is to be added, and the number of
long-integers needed.

    sub MySeeder
    {
        my $seed = $_[0];
        my $need = $_[1];

        while ($need--) {
            my $long_int = ...;      # Get seed data from your source
            push(@$seed, $long_int);
        }
    }

    # Call MySeeder for 256 long-ints, and
    #  then get the rest from random.org.
    srand(\&MySeeder => 256, 'random_org');

=item seed

When called without arguments, this function will return an array reference
containing the seed last sent to the PRNG.

When called with an array reference, the long-integer data contained
therein will be used to reseed the PRNG.

Together, these functions may be useful for setting up identical sequences
of random numbers based on the same seed.

=item state

When called without arguments, this function returns an array reference
containing the current state vector of the PRNG.

To reset the PRNG to a previous state, call this function with a previously
obtained state-vector array reference.

  # Get the current state of the PRNG
  my $state_vector = state();

  # Run the PRNG some more
  my $rand1 = rand32();

  # Restore the previous state of the PRNG
  state($state_vector);

  # Get another random number
  my $rand2 = rand32();

  # $rand1 and $rand2 will be equal.

CAUTION:  It should go without saying that you should not modify the values
in the state vector, but I'll say it anyway: "You should not modify the
values in the state vector."  'Nough said.

In conjunction with L<Data::Dumper> and C<do(file)>, this function can be
used to save and then reload the state vector between application runs.
See F<t/state1.t> and F<t/state2.t> in this module's distribution for an
example of this.

=back

=head1 DIAGNOSTICS

=over

=item @Math::Random::MT::Auto::errors

This array contains information related to any problem encountered while
trying to acquire seed data.  It can be examined after the module is loaded,
or after L</"srand"> is called.  After examining the messages, you can empty
the array if desired.

  @Math::Random::MT::Auto::errors = ();

=back

If you connect to the Internet through an HTTP proxy, then you must set the
C<http_proxy> variable in your environment when using the Internet seed
sources.  (See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site has a quota on the amount of data you can request in a
24-hour period.  (I don't know how big the quota is.)  Therefore, this
source may fail to provide any data if used too often.

If the module cannot acquire any seed data from the specified sources, then
the time() and PID will be used to seed the PRNG.

It is possible to seed the PRNG with more than 624 long-integers of data
(through the use of a seeding subroutine supplied to L</"srand">, or by
supplying a large array ref of data to L</"seed">).  However, doing so does
not make the PRNG "more random" as 624 long-integers more than covers all
the possible PRNG state vectors.

=head1 PERFORMANCE

This module is 50% faster than Math::Random::MT.  The file
F<samples/random>, included in this module's distribution, can be used to
compare timing results.

Depending on your connnection speed, acquiring seed data from the Internet
may take a couple of seconds.  This delay might be apparent when your
application is first started.  This is especially true if you specify the
C<hotbits> source twice (so as to get the full seed from the HotBits site)
as this results in two accesses to the Internet.  (If F</dev/urandom> is
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

OpenBSD random devices.
L<http://www.openbsd.org/cgi-bin/man.cgi?query=arandom&sektion=4&apropos=0&manpath=OpenBSD+Current&arch=>

FreeBSD random devices.
L<http://www.freebsd.org/cgi/man.cgi?query=random&sektion=4&apropos=0&manpath=FreeBSD+5.3-RELEASE+and+Ports>

Man pages for F</dev/random> and F</dev/urandom> on Unix/Linux/Cygwin/Solaris.
L<http://www.die.net/doc/linux/man/man4/random.4.html>

L<LWP::UserAgent>

L<Math::Random::MT>

L<Net::Random>

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
