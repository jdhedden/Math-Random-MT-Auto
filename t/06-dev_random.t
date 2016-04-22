# Tests for /dev/random

use Scalar::Util 'looks_like_number';

use Test::More;
if (! -e '/dev/random') {
    plan skip_all => '/dev/random not available';
} else {
    plan tests => 91;
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand irand warnings/, '/dev/random');
}

# Check for warnings
my @warnings;
eval { @warnings = warnings(1); };
ok(! $@, 'warnings(1) died: ' . $@);
if (grep { /exhausted/ } @warnings) {
    diag('/dev/random exhausted');
    @warnings = ();
}
ok(! @warnings, 'Seed errors: ' . join("\n", @warnings));

my ($rn, @rn);

# Test rand()
eval { $rn = rand(); };
ok(! $@,                    'rand() died: ' . $@);
ok(defined($rn),            'Got a random number');
ok(looks_like_number($rn),  'Is a number: ' . $rn);
ok($rn >= 0.0 && $rn < 1.0, 'In range: ' . $rn);

# Test several values from irand()
for (my $ii=0; $ii < 10; $ii++) {
    eval { $rn[$ii] = irand(); };
    ok(! $@,                        'irand() died: ' . $@);
    ok(defined($rn[$ii]),           'Got a random number');
    ok(looks_like_number($rn[$ii]), 'Is a number: ' . $rn[$ii]);
    ok(int($rn[$ii]) == $rn[$ii],   'Integer: ' . $rn[$ii]);
    for (my $jj=0; $jj < $ii; $jj++) {
        ok($rn[$jj] != $rn[$ii],    'Randomized');
    }
}

# EOF
