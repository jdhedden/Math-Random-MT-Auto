#!/usr/bin/perl

# Compares random number generation timings for Perl's core function,
# Math::Random::MT::Auto and Math::Random::MT (if available).

# Usage:  timings.pl [--local] [COUNT]
#       --local = Don't try internet sources

use strict;
use warnings;
no warnings 'void';

$| = 1;

use Math::Random::MT::Auto qw/rand irand srand seed warnings
                              gaussian exponential :!auto/;
use Time::HiRes;
use Config;

MAIN:
{
    # Command line arguments
    my $local = 0;
    my $count = 3120000;
    for my $arg (@ARGV) {
        if ($arg eq '--local') {
            $local = 1;
        } else {
            $count = 0 + $arg;
        }
    }

    my ($cnt, $start, $end);

    print("Random numbers generation timing\n");

    # Time Perl's srand()
    print("\n- Core -\n");
    my $seed = CORE::time() + $$;
    $start = Time::HiRes::time();
    CORE::srand($seed);
    $end = Time::HiRes::time();
    printf("srand:\t\t%f secs.\n", $end - $start);

    # Loop overhead
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
    }
    $end = Time::HiRes::time();
    my $overhead = $end - $start;

    # Time Perl's rand()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        CORE::rand();
    }
    $end = Time::HiRes::time();
    printf("rand:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    CORE::srand($seed);

    # Time Perl's rand(arg)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        CORE::rand(5);
    }
    $end = Time::HiRes::time();
    printf("rand(5):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Time Perl's rand() to product 64-bit randoms
    if ($Config{'uvsize'} == 8) {
        # Reseed
        CORE::srand($seed);

        $cnt = $count;
        $start = Time::HiRes::time();
        while ($cnt--) {
            (int(CORE::rand(4294967296)) << 32) | int(CORE::rand(4294967296));
        }
        $end = Time::HiRes::time();
        printf("rand [64-bit]:\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);
    }

    my @seed = @{seed()};       # Copy of existing seed

    my @warnings = warnings(1); # Clear any existing error messages

    if ($^O eq 'MSWin32') {
        # Call srand to load Win32::API
        srand('win32');
        # If errors, then ignore (probably not XP or no Win32::API)
        @warnings = warnings(1);
        if (! @warnings) {
            # Time our srand() for win32
            $start = Time::HiRes::time();
            srand('win32');
            $end = Time::HiRes::time();
            printf("srand:\t\t%f secs. (Win32 XP)\n", $end - $start);
            @seed = @{seed()};
        }

    } else {
        # Run srand once to load fcntl
        srand('/dev/random');
        @warnings = warnings(1);

        # Time our srand() for /dev/random
        print("\n- Math::Random::MT::Auto - Standalone PRNG -\n");
        $start = Time::HiRes::time();
        srand('/dev/random');
        $end = Time::HiRes::time();
        # If errors, then ignore (probably no /dev/random)
        @warnings = warnings(1);
        if (! @warnings) {
            printf("srand:\t\t%f secs. (/dev/random)\n", $end - $start);
            @seed = @{seed()};
        }
    }

    if (! $local) {
        # Call srand to load LWP::UserAgent
        @warnings = warnings(1);
        srand('random_org');
        # If errors, then ignore (probably no LWP::UserAgent)
        @warnings = warnings(1);
        if (! @warnings) {
            # Time our srand() for random.org
            $start = Time::HiRes::time();
            srand('random_org');
            $end = Time::HiRes::time();
            printf("srand:\t\t%f secs. (random.org)\n", $end - $start);
            @seed = @{seed()};
        }
    }

    # Time our irand()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        irand();
    }
    $end = Time::HiRes::time();
    printf("irand:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time our irand()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        Math::Random::MT::Auto::mt_irand();
    }
    $end = Time::HiRes::time();
    printf("::mt_irand:\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time our rand()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        rand();
    }
    $end = Time::HiRes::time();
    printf("rand:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time our rand(arg)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        rand(5);
    }
    $end = Time::HiRes::time();
    printf("rand(5):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time gaussian()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        gaussian();
    }
    $end = Time::HiRes::time();
    printf("gaussian:\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time gaussian(sd, mean)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        gaussian(3, 69);
    }
    $end = Time::HiRes::time();
    printf("gaussian(3,69):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time exponential()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        exponential();
    }
    $end = Time::HiRes::time();
    printf("expon:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time exponential(mean)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        exponential(5);
    }
    $end = Time::HiRes::time();
    printf("expon(5):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    seed(\@seed);

    # Time OO interface
    print("\n- Math::Random::MT::Auto - OO Interface -\n");
    my $rand;
    if ($^O eq 'MSWin32') {
        $start = Time::HiRes::time();
        $rand = Math::Random::MT::Auto->new('SOURCE' => ['win32']);
        $end = Time::HiRes::time();
        # If errors, then ignore (probably not XP or no Win32::API)
        @warnings = $rand->warnings(1);
        if (! @warnings) {
            printf("new:\t\t%f secs. (Win32 XP)\n", $end - $start);
        }

    } else {
        $start = Time::HiRes::time();
        $rand = Math::Random::MT::Auto->new('SOURCE' => ['/dev/random']);
        $end = Time::HiRes::time();
        # If errors, then ignore (probably no /dev/random)
        @warnings = $rand->warnings(1);
        if (! @warnings) {
            printf("new:\t\t%f secs. (/dev/random)\n", $end - $start);
        }
    }

    if (! $local) {
        # Time our srand() for random.org
        $start = Time::HiRes::time();
        $rand = Math::Random::MT::Auto->new('SOURCE' => ['random_org']);
        $end = Time::HiRes::time();
        # If errors, then ignore (probably no LWP::UserAgent)
        @warnings = $rand->warnings(1);
        if (! @warnings) {
            printf("new:\t\t%f secs. (random.org)\n", $end - $start);
        }
    }

    # Reseed
    $rand->seed(\@seed);

    # Time our irand()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->irand();
    }
    $end = Time::HiRes::time();
    printf("irand:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # Time our rand()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->rand();
    }
    $end = Time::HiRes::time();
    printf("rand:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # Time our rand(arg)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->rand(5);
    }
    $end = Time::HiRes::time();
    printf("rand(5):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # Time our gaussian()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->gaussian();
    }
    $end = Time::HiRes::time();
    printf("gaussian:\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # Time gaussian(sd, mean)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->gaussian(3, 69);
    }
    $end = Time::HiRes::time();
    printf("gaussian(3,69):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # Time our exponential()
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->exponential();
    }
    $end = Time::HiRes::time();
    printf("expon:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # Time exponential(mean)
    $cnt = $count;
    $start = Time::HiRes::time();
    while ($cnt--) {
        $rand->exponential(5);
    }
    $end = Time::HiRes::time();
    printf("expon(5):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

    # Reseed
    $rand->seed(\@seed);

    # See if Math::Random::MT is available
    eval { require Math::Random::MT; };
    if (! $@) {
        # Time its new(@seed) method
        print("\n- Math::Random::MT -\n");
        $start = Time::HiRes::time();
        $rand = Math::Random::MT->new(@seed);
        $end = Time::HiRes::time();
        printf("new:\t\t%f secs. (+ seed acquisition time)\n", $end - $start);

        # Time its rand() method
        $cnt = $count;
        $start = Time::HiRes::time();
        while ($cnt--) {
            $rand->rand();
        }
        $end = Time::HiRes::time();
        printf("rand:\t\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

        # Reseed
        $rand = Math::Random::MT->new(@seed);

        # Time its rand(arg) method
        $cnt = $count;
        $start = Time::HiRes::time();
        while ($cnt--) {
            $rand->rand(5);
        }
        $end = Time::HiRes::time();
        printf("rand(5):\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);

        # Time its rand() to product 64-bit randoms
        if ($Config{'uvsize'} == 8) {
            # Reseed
            $rand = Math::Random::MT->new(@seed);

            $cnt = $count;
            $start = Time::HiRes::time();
            while ($cnt--) {
                (int($rand->rand(4294967296)) << 32) | int($rand->rand(4294967296));
            }
            $end = Time::HiRes::time();
            printf("rand [64-bit]:\t%f secs. (%d)\n", ($end-$start)-$overhead, $count);
        }
    }
}

exit(0);

# EOF