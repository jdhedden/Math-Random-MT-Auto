# Module makefile for Math::Random::MT::Auto

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
    return $cmd if (-x $cmd or $cmd = MM->maybe_command($cmd));
    for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), '.') {
        my $abs = File::Spec->catfile($dir, $_[0]);
        return $abs if (-x $abs or $abs = MM->maybe_command($abs));
    }
    return;
}

sub have_cc
{
    my @chunks = split(/ /, $Config::Config{cc}) or return;
    # $Config{cc} may contain args; try to find out the program part
    while (@chunks) {
        return check_cc("@chunks") || (pop(@chunks), next);
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
    PREREQ_PM         => { Scalar::Util => 1.16 },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Math/Random/MT/Auto.pm',
       AUTHOR         => 'Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>') : ()),
);

# EOF
