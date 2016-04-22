# Verify state() Function Part 2: The Restoration

use Scalar::Util 'looks_like_number';

use Test::More;

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand32 state/);
};

# Read state and numbers from file
if (! -e 'state_data.tmp') {
    plan(skip_all => 'state file not found');
}
our ($state, @rn);
my $rc = do('state_data.tmp');
unlink('state_data.tmp');
if ($@ || ! $rc) {
    plan(skip_all => 'failure parsing state file');
} else {
    plan(tests => 2501);
}


# Set state
eval { state($state); };
ok(! $@, 'Set state() died: ' . $@);


# Get some numbers to compare
for (my $ii=0; $ii < 500; $ii++) {
    eval { $rn = rand32(); };
    ok(! $@,                  'rand32() died: ' . $@);
    ok(defined($rn),          'Got a random number');
    ok(looks_like_number($rn),'Is a number: ' . $rn);
    ok(int($rn) == $rn,       'Integer: ' . $rn);
    ok($rn == $rn[$ii],       'Numbers match');
}

# EOF
