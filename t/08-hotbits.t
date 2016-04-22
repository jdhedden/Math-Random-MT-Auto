# Tests for HotBits site

use strict;
use warnings;

use Scalar::Util 'looks_like_number';

use Test::More;
eval { require LWP::UserAgent; };
if ($@) {
    plan skip_all => 'LWP::UserAgent not available';
} else {
    # See if we can connect to HotBits
    my $res;
    eval {
        # Create user agent
        my $ua = LWP::UserAgent->new( timeout => 3, env_proxy => 1 );
        # Create request to random.org
        my $req = HTTP::Request->new(GET => "http://www.fourmilab.ch/cgi-bin/uncgi/Hotbits?fmt=bin&nbytes=4");
        # Get the data
        $res = $ua->request($req);
    };
    if ($@) {
        plan skip_all => "Failure contacting HotBits: $@";
    } elsif ($res->is_success) {
        if ($res->content =~ /exceeded your 24-hour quota/) {
            plan skip_all => $res->content;
        } else {
            plan tests => 89;
        }
    } else {
        plan skip_all => 'Failure getting data from HotBits: ' . $res->status_line;
    }
}

my @WARN;
BEGIN {
    # Warning signal handler
    $SIG{__WARN__} = sub { push(@WARN, @_); };

    use_ok('Math::Random::MT::Auto', qw/rand irand get_seed/, 'hotbits');
}

# Check for warnings
if (@WARN) {
    if (my ($exceeded) = grep { $_ =~ /exceeded your 24-hour quota/ } @WARN) {
        diag($exceeded);
    }
    @WARN = grep { $_ !~ /exceeded your 24-hour quota/ &&
                   $_ !~ /Partial seed/ } @WARN;
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
