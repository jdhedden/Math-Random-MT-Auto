# Tests the Math::Random::MT::Auto::Range class

use strict;
use warnings;

use Scalar::Util 'looks_like_number';

use Test::More tests => 217;
use Config;
use threads;

BEGIN {
    use_ok('Math::Random::MT::Auto::Range');
}

# Create PRNG object
my $prng;
eval { $prng = Math::Random::MT::Auto::Range->new(lo=>100, hi=>199); };
if (! ok(! $@, '->new works')) {
    diag('->new died: ' . $@);
}
isa_ok($prng, 'Math::Random::MT::Auto');
isa_ok($prng, 'Math::Random::MT::Auto::Range');
can_ok($prng, qw/rand irand gaussian exponential erlang poisson binomial
                 shuffle srand seed state warnings new range_type range rrand/);
my @warnings;
eval { @warnings = $prng->warnings(1); };
if (! ok(! $@, 'Get warnings')) {
    diag('warnings(1) died: ' . $@);
}
if (! ok(! @warnings, 'Acquired seed data')) {
    diag('Seed warnings: ' . join(' | ', @warnings));
}
ok($prng->range_type() eq 'INTEGER', 'Int range type');
my ($lo, $hi) = $prng->range();
ok($lo == 100 && $hi == 199, "Range: $lo $hi");

# Test several values from rrand()
my $rr;
for my $ii (0 .. 9) {
    eval { $rr = $prng->rrand(); };
    ok(! $@,                        '$prng->rrand() died: ' . $@);
    ok(defined($rr),                'Got a random number');
    ok(looks_like_number($rr),      'Is a number: ' . $rr);
    ok(int($rr) == $rr,             'Integer: ' . $rr);
    ok($rr >= 100 && $rr <= 199,    'In range: ' . $rr);
}

# Test several values from irand()
for my $ii (0 .. 9) {
    eval { $rr = $prng->irand(); };
    ok(! $@,                        '$prng->irand() died: ' . $@);
    ok(defined($rr),                'Got a random number');
    ok(looks_like_number($rr),      'Is a number: ' . $rr);
    ok(int($rr) == $rr,             'Integer: ' . $rr);
    ok($rr >= 0,                    'Postive int: ' . $rr);
}

# New PRNG
my $prng2 = $prng->new(type=>'double');
isa_ok($prng2, 'Math::Random::MT::Auto');
isa_ok($prng2, 'Math::Random::MT::Auto::Range');
can_ok($prng2, qw/rand irand gaussian exponential erlang poisson binomial
                 shuffle srand seed state warnings new range_type range rrand/);
eval { @warnings = $prng2->warnings(1); };
if (! ok(! $@, 'Get warnings')) {
    diag('warnings(1) died: ' . $@);
}
if (! ok(! @warnings, 'Acquired seed data')) {
    diag('Seed warnings: ' . join(' | ', @warnings));
}
ok($prng2->range_type() eq 'DOUBLE', 'Double range type');
($lo, $hi) = $prng2->range();
ok($lo == 100 && $hi == 199, "Range: $lo $hi");

# Test several values from rrand()
my $ints = 0;
for my $ii (0 .. 9) {
    eval { $rr = $prng2->rrand(); };
    ok(! $@,                    '$prng->rrand() died: ' . $@);
    ok(defined($rr),            'Got a random number');
    ok(looks_like_number($rr),  'Is a number: ' . $rr);
    if (int($rr) == $rr) {
        $ints++;
    }
    ok($rr >= 100 && $rr < 199, 'In range: ' . $rr);
}
ok($ints < 10, 'Rands not ints: ' . $ints);


### Threads with subclass

SKIP: {
if (! $Config{useithreads}) {
    skip 'Threads not supported', 60;
} elsif ($] < 5.007002) {
    skip 'Not thread-safe prior to 5.7.2', 60;
}

# Get random numbers from thread
my $rands = threads->create(
                        sub {
                            my @rands;
                            for (0 .. 9) {
                                my $rand = $prng->rrand();
                                push(@rands, $rand);
                            }
                            return (\@rands);
                        }
                    )->join();

# Check that parent gets the same numbers
my $rand;
for my $ii (0 .. 9) {
    eval { $rand = $prng->rrand(); };
    ok(! $@,                         '$prng->rrand() died: ' . $@);
    ok(defined($rand),               'Got a random number');
    ok(looks_like_number($rand),     'Is a number: ' . $rand);
    ok(int($rand) == $rand,          'Integer: ' . $rand);
    ok($rand >= 100 && $rand <= 199, 'In range: ' . $rand);
    ok($$rands[$ii] == $rand,        'Values equal: ' . $$rands[$ii] . ' ' . $rand);
}
}

# EOF
