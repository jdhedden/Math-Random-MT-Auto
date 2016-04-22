# Verify state() Function Part 1: The Saving

use Test::More tests => 4003;
use Scalar::Util 'looks_like_number';
use Data::Dumper;

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand32 state/);
};


# Work the PRNG a bit
my $rn;
for (my $ii=0; $ii < 500; $ii++) {
    eval { $rn = rand32(); };
    ok(! $@,                  'rand32() died: ' . $@);
    ok(defined($rn),          'Got a random number');
    ok(looks_like_number($rn),'Is a number: ' . $rn);
    ok(int($rn) == $rn,       'Integer: ' . $rn);
}


# Get state
my $state;
eval { $state = state(); };
ok(! $@, 'Get state() died: ' . $@);
ok(ref($state) eq 'ARRAY', 'State is array ref');


# Get some numbers to save
my @rn;
for (my $ii=0; $ii < 500; $ii++) {
    eval { $rn = rand32(); };
    ok(! $@,                  'rand32() died: ' . $@);
    ok(defined($rn),          'Got a random number');
    ok(looks_like_number($rn),'Is a number: ' . $rn);
    ok(int($rn) == $rn,       'Integer: ' . $rn);
    push(@rn, $rn);
}


# Save state and numbers to file
open(FH, '>state_data.tmp');
print(FH Data::Dumper->Dump([$state, \@rn], ['state', '*rn']));
print(FH "1;\n");
close(FH)

# EOF
