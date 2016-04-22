use ExtUtils::MakeMaker;

if ($] < 5.006) {
    die("Math::Random::MT::Auto requires Perl v5.6.0 or higher\n");
}

WriteMakefile(
    NAME              => 'Math::Random::MT::Auto',
    OBJECT            => 'MRMA.o',
    VERSION           => 1.34,
    VERSION_FROM      => 'lib/Math/Random/MT/Auto.pm',
    PREREQ_PM         => { Scalar::Util => 1.16 },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Math/Random/MT/Auto.pm',
       AUTHOR         => 'Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>') : ()),
);
