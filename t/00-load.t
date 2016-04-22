use strict;
use warnings;

use Test::More 'no_plan';

BEGIN {
    use_ok('Math::Random::MT::Auto', ':!auto');
}

if (Math::Random::MT::Auto->VERSION) {
    diag('Testing Math::Random::MT::Auto ' . Math::Random::MT::Auto->VERSION);
}

# EOF
