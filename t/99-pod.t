use strict;
use warnings;

use Test::More 'no_plan';

SKIP: {
    eval 'use Test::Pod 1.26';
    skip('Test::Pod 1.26 required for testing POD', 1) if $@;

    pod_file_ok('blib/lib/Math/Random/MT/Auto.pm');
    pod_file_ok('blib/lib/Math/Random/MT/Auto/Range.pm');
}

SKIP: {
    eval 'use Test::Pod::Coverage 1.08';
    skip('Test::Pod::Coverage 1.08 required for testing POD coverage', 1) if $@;

    pod_coverage_ok('Math::Random::MT::Auto',
                    {
                        'trustme' => [
                            qr/^(?:array|as_string|bool)$/,
                        ],
                        'private' => [
                            qr/^(import|bootstrap)$/,
                            qr/^_/
                        ]
                    }
    );

    pod_coverage_ok('Math::Random::MT::Auto::Range',
                    {
                        'trustme' => [
                            qr/^(?:array|as_string|bool)$/,
                        ],
                        'private' => [
                            qr/^_/,
                        ]
                    }
    );
}

# EOF
