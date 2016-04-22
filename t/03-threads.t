# Tests for OO thread safety

use Scalar::Util 'looks_like_number';

use Test::More;
use Config;
use threads;

if (! $Config{useithreads}) {
    plan(skip_all => 'Threads not supported');
} elsif ($] < 5.007002) {
    plan(skip_all => 'Not thread-safe prior to 5.7.2');
} elsif ($] < 5.008007) {
    plan(tests => 54);
} else {
    plan(tests => 53);
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
can_ok($prng, qw/rand irand gaussian srand seed state warnings/);

# Thread cloning workaround for < 5.8.7
if ($] < 5.008007) {
    $prng->{'STATE'} = $prng->state();
    ok(ref($prng->{'STATE'}) eq 'ARRAY', 'Thread cloning workaround');
}

# Get random numbers from thread
my $rands = threads->create(
                        sub {
                            my @rands;
                            for (my $ii=0; $ii<10; $ii++) {
                                my $rand = $prng->irand();
                                push(@rands, $rand);
                            }
                            return (\@rands);
                        }
                    )->join();

# Check that parent gets the same numbers
my $rand;
for (my $ii=0; $ii<10; $ii++) {
    eval { $rand = $prng->irand(); };
    ok(! $@,                     'irand() died: ' . $@);
    ok(defined($rand),           'Got a random number');
    ok(looks_like_number($rand), 'Is a number: ' . $rand);
    ok(int($rand) == $rand,      'Integer: ' . $rand);
    ok($$rands[$ii] == $rand,    'Values equal');
}

# EOF
