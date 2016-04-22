# Tests for RandomNumbers.info site

use strict;
use warnings;

use Scalar::Util 1.10 'looks_like_number';

use Test::More;
eval { require LWP::UserAgent; };
if ($@) {
    plan skip_all => 'LWP::UserAgent not available';
} else {
    # See if we can connect
    my $res;
    eval {
        my $ua = LWP::UserAgent->new( timeout => 5, env_proxy => 1 );
        my $req = HTTP::Request->new(GET => "http://www.randomnumbers.info/cgibin/wqrng?limit=255&amount=1");
        $res = $ua->request($req);
    };
    if ($@) {
        plan skip_all => "Failure contacting RandomNumbers.info: $@";
    } elsif ($res->is_success) {
        plan tests => 89;
    } else {
        plan skip_all => 'Failure getting data from RandomNumbers.info: ' . $res->status_line;
    }
}

my @WARN;
BEGIN {
    # Warning signal handler
    $SIG{__WARN__} = sub { push(@WARN, @_); };

    use_ok('Math::Random::MT::Auto', qw/rand irand get_seed/, 'rn_info');
}

# Check for warnings
if (@WARN) {
    @WARN = grep { $_ !~ /Partial seed/ } @WARN;
    if (@WARN) {
        diag('Seed warnings: ' . join(' | ', @WARN));
    }
} else {
    ok(@WARN, 'No short seed error');
    diag('seed: ' . scalar(@{get_seed()}));
}
undef(@WARN);

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
