# Tests for Math::Random::MT::Net module

use Test::More tests => 14;
BEGIN { use_ok('Math::Random::MT::Net') };

use Scalar::Util 'looks_like_number';

my ($err, $rand, $rand2, $rand3);

# Set up warning handler
$SIG{'__WARN__'} = sub { $err = $_[0]; };

eval { $rand = rand(); };

# Report if can't talk to random.org
if ($err) {
    diag("\n$err");
}

ok(! $@,                     'rand() died: '.$@);
ok(defined($rand),           'Acquired a random number');
ok(looks_like_number($rand), 'Random result is a number');
ok($rand >= 0 && $rand < 1,  'Random number in range 0..1');

eval { $rand2 = rand(); };
ok(! $@,                     'rand() died: '.$@);
ok(defined($rand2),          'Acquired a random number');
ok(looks_like_number($rand2),'Random result is a number');
ok($rand2 >= 0 && $rand2 < 1,'Random number in range 0..1');

eval { $rand3 = rand(); };
ok(! $@,                     'rand() died: '.$@);
ok(defined($rand3),          'Acquired a random number');
ok(looks_like_number($rand3),'Random result is a number');
ok($rand3 >= 0 && $rand3 < 1,'Random number in range 0..1');

ok($rand != $rand2 && $rand2 != $rand3, 'Random results');

# EOF
