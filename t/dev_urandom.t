# Tests for /dev/urandom

use Scalar::Util 'looks_like_number';

use Test::More;
if (! -e '/dev/urandom') {
    plan skip_all => '/dev/urandom not available';
} else {
    plan tests => 90;
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand rand32 dev_urandom/);
}

ok(! @Math::Random::MT::Auto::errors,
        'Seed errors: ' . join("\n", @Math::Random::MT::Auto::errors));

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
