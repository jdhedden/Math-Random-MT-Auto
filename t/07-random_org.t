# Tests for random.org site

use Scalar::Util 'looks_like_number';

use Test::More;
eval { require LWP::UserAgent; };
if ($@) {
    plan skip_all => 'LWP::UserAgent not available';
} else {
    plan tests => 90;
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand irand warnings/, 'random_org');
}

# Check for warnings
my @warnings;
eval { @warnings = warnings(1); };
if (! ok(! $@, 'Get warnings')) {
    diag('warnings(1) died: ' . $@);
}
if (@warnings) {
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
