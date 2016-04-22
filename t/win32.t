# Tests for Windows XP random source

use Scalar::Util 'looks_like_number';

use Test::More;
if ($^O ne 'MSWin32') {
    plan(skip_all => 'Not Win32');
} else {
    my ($id, $major, $minor) = (Win32::GetOSVersion())[4,1,2];
    if (defined($minor) &&
        (($id > 2) ||
         ($id == 2 && $major > 5) ||
         ($id == 2 && $major == 5 && $id >= 1)))
    {
        plan(tests => 91);
    } else {
        plan(skip_all => 'Not Win XP');
    }
}

BEGIN {
    use_ok('Math::Random::MT::Auto', qw/rand rand32 warnings/, 'win32');
}

# Check for warnings
my @warnings;
eval { @warnings = warnings(1); };
ok(! $@, 'warnings(1) died: ' . $@);
ok(! @warnings, 'Seed errors: ' . join("\n", @warnings));

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
