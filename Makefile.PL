# Module makefile for Math::Random::MT::Auto (using ExtUtils::MakeMaker)

use strict;
use warnings;
use ExtUtils::MakeMaker;
use File::Spec ();

# First, check for manatory Perl version
if ($] < 5.006) {
    die("Math::Random::MT::Auto requires Perl 5.6.0 or higher\n");
}


# Next, check for C compiler
sub check_cc
{
    my $cmd = $_[0];
    if (-x $cmd or MM->maybe_command($cmd)) {
        return (1);       # CC command found
    }
    for my $dir (File::Spec->path(), '.') {
        my $abs = File::Spec->catfile($dir, $cmd);
        if (-x $abs or MM->maybe_command($abs)) {
            return (1);   # CC command found
        }
    }
    return;
}

sub have_cc
{
    eval { require Config_m; };     # ExtUtils::FakeConfig (+ ActivePerl)
    if ($@) {
        eval { require Config; };   # Everyone else
    }
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


# Finally, construct make file
WriteMakefile(
    'NAME'          => 'Math::Random::MT::Auto',
    'AUTHOR'        => 'Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>',
    'VERSION_FROM'  => 'lib/Math/Random/MT/Auto.pm',
    'ABSTRACT_FROM' => 'lib/Math/Random/MT/Auto.pm',
    'PREREQ_PM'     => { 'Scalar::Util' => '1.16' },
    'OBJECT'        => 'MRMA.o',
    (($ExtUtils::MakeMaker::VERSION < 6.25) ?
        ('PL_FILES'      => { })                : ()),
    (($ExtUtils::MakeMaker::VERSION > 6.30) ?
        ('LICENSE'       => 'unrestricted')     : ()),
);


# Add additional target to Makefile
sub MY::postamble
{
    return <<'_VCHECK_';
# Check version strings in various files
vcheck:
	@echo "Version is ${VERSION}"
	@if ! head -3 Changes | tail -1 | grep ^${VERSION} >/dev/null; then echo "Version error in Changes"; fi
	@if ! head -1 README | grep ${VERSION}$ >/dev/null; then echo "Version error in README"; fi
	@if ! grep "VERSION = '${VERSION}'" lib/Math/Random/MT/Auto.pm >/dev/null; then echo "Version error in lib/Math/Random/MT/Auto.pm"; fi
	@if ! grep "version ${VERSION}" lib/Math/Random/MT/Auto.pm >/dev/null; then echo "Version error in POD of lib/Math/Random/MT/Auto.pm"; fi
	@if ! grep "VERSION = '${VERSION}'" lib/Math/Random/MT/Auto/Range.pm >/dev/null; then echo "Version error in lib/Math/Random/MT/Auto/Range.pm"; fi
_VCHECK_
}

# EOF
