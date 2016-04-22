# Tests for OO thread safety

use strict;
use warnings;

use Scalar::Util 'looks_like_number';

use Test::More;
use Config;
use threads;

if (! $Config{useithreads}) {
    plan(skip_all => 'Threads not supported');
} elsif ($] < 5.007002) {
    plan(skip_all => 'Not thread-safe prior to 5.7.2');
} else {
    plan(tests => 94);
}

BEGIN {
    use_ok('Math::Random::MT::Auto');
}

# 'Empty subclass' test  (cf. perlmodlib)
@IMA::Subclass::ISA = 'Math::Random::MT::Auto';

# Create PRNG
my $prng;
eval { $prng = IMA::Subclass->new(); };
if (! ok(! $@, '->new worked')) {
    diag('->new died: ' . $@);
}
isa_ok($prng, 'Math::Random::MT::Auto');
isa_ok($prng, 'IMA::Subclass');
can_ok($prng, qw/rand irand gaussian exponential erlang poisson binomial
                 shuffle srand get_seed set_seed get_state set_state/);

# Get random numbers from thread
my $rands = threads->create(
                        sub {
                            my @rands;
                            for (0 .. 9) {
                                my $rand = $prng->irand();
                                push(@rands, $rand);
                            }
                            for (0 .. 9) {
                                my $rand = $prng->rand(3);
                                push(@rands, $rand);
                            }
                            return (\@rands);
                        }
                    )->join();

# Check that parent gets the same numbers
my $rand;
for my $ii (0 .. 9) {
    eval { $rand = $prng->irand(); };
    ok(! $@,                     '$prng->irand() died: ' . $@);
    ok(defined($rand),           'Got a random number');
    ok(looks_like_number($rand), 'Is a number: ' . $rand);
    ok(int($rand) == $rand,      'Integer: ' . $rand);
    ok($$rands[$ii] == $rand,    'Values equal: ' . $$rands[$ii] . ' ' . $rand);
}
for my $ii (10 .. 19) {
    eval { $rand = $prng->rand(3); };
    ok(! $@,                     '$prng->rand(3) died: ' . $@);
    ok(defined($rand),           'Got a random number');
    ok(looks_like_number($rand), 'Is a number: ' . $rand);
    ok($$rands[$ii] == $rand,    'Values equal: ' . $$rands[$ii] . ' ' . $rand);
}

# EOF
