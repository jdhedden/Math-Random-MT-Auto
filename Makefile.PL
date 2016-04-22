# Module makefile for Math::Random::MT::Auto (using ExtUtils::MakeMaker)

use strict;
use warnings;
use ExtUtils::MakeMaker;
use Config ();
use File::Spec ();

if ($] < 5.006) {
    die("Math::Random::MT::Auto requires Perl v5.6.0 or higher\n");
}

# Check for C compiler
sub check_cc
{
    my $cmd = $_[0];
    if (-x $cmd or MM->maybe_command($cmd)) {
        return (1);       # CC command found
    }
    for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), '.') {
        my $abs = File::Spec->catfile($dir, $cmd);
        if (-x $abs or MM->maybe_command($abs)) {
            return (1);   # CC command found
        }
    }
    return;
}

sub have_cc
{
    my @chunks = split(/ /, $Config::Config{cc});
    # $Config{cc} may contain args; try to find out the program part
    while (@chunks) {
        if (check_cc("@chunks")) {
            return (1);   # CC command found
        }
        pop(@chunks);
    }
    return;
}

if (! have_cc()) {
    die("No 'C' compiler found to build Math::Random::MT::Auto\n");
}


WriteMakefile(
    NAME              => 'Math::Random::MT::Auto',
    OBJECT            => 'MRMA.o',
    VERSION_FROM      => 'lib/Math/Random/MT/Auto.pm',
    PREREQ_PM         => { 'Scalar::Util' => 1.16 },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Math/Random/MT/Auto.pm',
       AUTHOR         => 'Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>') : ()),
);

# EOF
