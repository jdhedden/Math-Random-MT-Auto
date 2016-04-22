# Tests for HotBits site

use Scalar::Util 'looks_like_number';

use Test::More;
eval { require LWP::UserAgent; };
if ($@) {
    plan skip_all => 'LWP::UserAgent not available';
} else {
    plan tests => 91;
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand rand32 seed warnings/, 'hotbits');
}

# Check for warnings
my @warnings;
eval { @warnings = warnings(1); };
ok(! $@, 'warnings(1) died: ' . $@);
if (@warnings) {
    if ($warnings[0] =~ /exceeded your 24-hour quota/) {
        diag(shift(@warnings));
    }
    if ($warnings[0] =~ /Partial seed/) {
        shift(@warnings);
    }
    ok(! @warnings, 'Seed errors: ' . join("\n", @warnings));
} else {
    ok(@warnings, 'No short seed error');
    diag('seed: ' . scalar(@{seed()}));
}

my ($rn, @rn);

# Test rand()
eval { $rn = rand(); };
ok(! $@,                    'rand() died: ' . $@);
ok(defined($rn),            'Got a random number');
ok(looks_like_number($rn),  'Is a number: ' . $rn);
ok($rn >= 0.0 && $rn < 1.0, 'In range: ' . $rn);

# Test several values from rand32()
for (my $ii=0; $ii < 10; $ii++) {
    eval { $rn[$ii] = rand32(); };
    ok(! $@,                        'rand32() died: ' . $@);
    ok(defined($rn[$ii]),           'Got a random number');
    ok(looks_like_number($rn[$ii]), 'Is a number: ' . $rn[$ii]);
    ok(int($rn[$ii]) == $rn[$ii],   'Integer: ' . $rn[$ii]);
    for (my $jj=0; $jj < $ii; $jj++) {
        ok($rn[$jj] != $rn[$ii],    'Randomized');
    }
}

# EOF
