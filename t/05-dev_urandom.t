# Tests for /dev/urandom

use Scalar::Util 'looks_like_number';

use Test::More;
if (! -e '/dev/urandom') {
    plan skip_all => '/dev/urandom not available';
} else {
    plan tests => 91;
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand irand get_warnings/, '/dev/urandom');
}

# Check for warnings
my @warnings;
eval { @warnings = get_warnings(1); };
if (! ok(! $@, 'Get warnings')) {
    diag('get_warnings(1) died: ' . $@);
}
if (! ok(! @warnings, 'Acquired seed data')) {
    diag('Seed warnings: ' . join(' | ', @warnings));
}

my ($rn, @rn);

# Test rand()
eval { $rn = rand(); };
ok(! $@,                    'rand() died: ' . $@);
ok(defined($rn),            'Got a random number');
ok(looks_like_number($rn),  'Is a number: ' . $rn);
ok($rn >= 0.0 && $rn < 1.0, 'In range: ' . $rn);

# Test several values from irand()
for my $ii (0 .. 9) {
    eval { $rn[$ii] = irand(); };
    ok(! $@,                        'irand() died: ' . $@);
    ok(defined($rn[$ii]),           'Got a random number');
    ok(looks_like_number($rn[$ii]), 'Is a number: ' . $rn[$ii]);
    ok(int($rn[$ii]) == $rn[$ii],   'Integer: ' . $rn[$ii]);
    for my $jj (0 .. $ii-1) {
        ok($rn[$jj] != $rn[$ii],    'Randomized');
    }
}

# EOF
