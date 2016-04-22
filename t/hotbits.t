# Tests for HotBits site

use Scalar::Util 'looks_like_number';

use Test::More;
eval { require LWP::UserAgent; };
if ($@) {
    plan skip_all => 'LWP::UserAgent not available';
} else {
    plan tests => 90;
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand rand32 hotbits/);
}

if (@Math::Random::MT::Auto::errors) {
    if ($Math::Random::MT::Auto::errors[0] =~ /exceeded your 24-hour quota/) {
        diag(shift(@Math::Random::MT::Auto::errors));
    }
    if ($Math::Random::MT::Auto::errors[0] =~ /Full seed not acquired/) {
        shift(@Math::Random::MT::Auto::errors);
    }
    ok(! @Math::Random::MT::Auto::errors,
            'Seed errors: ' . join("\n", @Math::Random::MT::Auto::errors));
} else {
    ok(@Math::Random::MT::Auto::errors, 'No short seed error');
    diag('seed: ' . scalar(@Math::Random::MT::Auto::seed));
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
    ok(looks_like_number($rn[$ii]), 'Is a number: ' . $rn);
    ok(int($rn[$ii]) == $rn[$ii],   'Integer: ' . $rn);
    for (my $jj=0; $jj < $ii; $jj++) {
        ok($rn[$jj] != $rn[$ii],    'Randomized');
    }
}

# EOF