# Verify state() Function Part 1: The Saving

use Test::More tests => 2005;
use Scalar::Util 'looks_like_number';
use Data::Dumper;

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/irand get_state set_state/);
};


# Work the PRNG a bit
my $rn;
for (1 .. 500) {
    eval { $rn = irand(); };
    ok(! $@,                  'irand() died: ' . $@);
    ok(defined($rn),          'Got a random number');
    ok(looks_like_number($rn),'Is a number: ' . $rn);
    ok(int($rn) == $rn,       'Integer: ' . $rn);
}


# Get state
our $state;
eval { $state = get_state(); };
ok(! $@, 'get_state() died: ' . $@);
ok(ref($state) eq 'ARRAY', 'State is array ref');


# Get some numbers to save
our @rn;
for (1 .. 500) {
    push(@rn, irand());
}


# Save state and numbers to file
if (open(FH, '>state_data.tmp')) {
    print(FH Data::Dumper->Dump([$state, \@rn], ['state', '*rn']));
    print(FH "1;\n");
    close(FH);
} else {
    diag('Failure writing state to file');
}

# Clear vars
undef($state);
undef(@rn);

# Read state and numbers from file
my $rc = do('state_data.tmp');
unlink('state_data.tmp');

# Set state
eval { set_state($state); };
ok(! $@, 'set_state() died: ' . $@);

# Compare numbers after restoration of state
my @rn2;
for (1 .. 500) {
    push(@rn2, irand());
}
is_deeply(\@rn, \@rn2, 'Same results after state restored');

# EOF
