# set state
# read numbers from file
# generate numbers
# compare



# Verify state() Function Part 2: The Restoration

use Test::More tests => 2502;
use Scalar::Util 'looks_like_number';
use Data::Dumper;

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand32 state/);
};

# Read state and numbers from file
our ($state, @rn);
do('state_data.tmp');
unlink('state_data.tmp');


# Set state
eval { state($state); };
ok(! $@, 'Set state() died: ' . $@);


# Get some numbers to save
for (my $ii=0; $ii < 500; $ii++) {
    eval { $rn = rand32(); };
    ok(! $@,                  'rand32() died: ' . $@);
    ok(defined($rn),          'Got a random number');
    ok(looks_like_number($rn),'Is a number: ' . $rn);
    ok(int($rn) == $rn,       'Integer: ' . $rn);
    ok($rn == $rn[$ii],       'Numbers match');
}



# EOF
