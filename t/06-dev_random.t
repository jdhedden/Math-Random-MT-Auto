# Tests for /dev/random

use strict;
use warnings;

use Test::More;
if (! -e '/dev/random') {
    plan skip_all => '/dev/random not available';
} else {
    plan tests => 90;
}

my @WARN;
BEGIN {
    # Warning signal handler
    $SIG{__WARN__} = sub { push(@WARN, @_); };

    use_ok('Math::Random::MT::Auto', qw(rand irand), '/dev/random');
}

# Check for warnings
if (grep { /exhausted/ } @WARN) {
    diag('/dev/random exhausted');
    undef(@WARN);
}
if (! ok(! @WARN, 'Acquired seed data')) {
    diag('Seed warnings: ' . join(' | ', @WARN));
}
undef(@WARN);

my ($rn, @rn);

# Test rand()
eval { $rn = rand(); };
ok(! $@,                    'rand() died: ' . $@);
ok(defined($rn),            'Got a random number');
ok(Scalar::Util::looks_like_number($rn),  'Is a number: ' . $rn);
ok($rn >= 0.0 && $rn < 1.0, 'In range: ' . $rn);

# Test several values from irand()
for my $ii (0 .. 9) {
    eval { $rn[$ii] = irand(); };
    ok(! $@,                        'irand() died: ' . $@);
    ok(defined($rn[$ii]),           'Got a random number');
    ok(Scalar::Util::looks_like_number($rn[$ii]), 'Is a number: ' . $rn[$ii]);
    ok(int($rn[$ii]) == $rn[$ii],   'Integer: ' . $rn[$ii]);
    for my $jj (0 .. $ii-1) {
        ok($rn[$jj] != $rn[$ii],    'Randomized');
    }
}

# EOF
