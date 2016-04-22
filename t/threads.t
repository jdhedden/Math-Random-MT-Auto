# Tests for OO thread safety

use Scalar::Util 'looks_like_number';

use Test::More;
use Config;
use threads;

if (! $Config{useithreads}) {
    plan(skip_all => 'Threads not supported');
} else {
    plan(tests => 52);
}

BEGIN {
    use_ok('Math::Random::MT::Auto');
}

# Create PRNG
my $prng;
eval { $prng = Math::Random::MT::Auto->new(); };
ok(! $@, 'Creating rand obj failed: ' . $@);
ok(ref($prng), 'Got rand obj');

# Get random numbers from thread
my $rands = threads->create(
                        sub {
                            my @rands;
                            for (my $ii=0; $ii<10; $ii++) {
                                my $rand = $prng->rand32();
                                push(@rands, $rand);
                            }
                            return (\@rands);
                        }
                    )->join();

# Check that parent gets the same numbers
my $rand;
for (my $ii=0; $ii<10; $ii++) {
    eval { $rand = $prng->rand32(); };
    ok(! $@,                     'rand32() died: ' . $@);
    ok(defined($rand),           'Got a random number');
    ok(looks_like_number($rand), 'Is a number: ' . $rand);
    ok(int($rand) == $rand,      'Integer: ' . $rand);
    ok($$rands[$ii] == $rand,    'Values equal');
}

# EOF
