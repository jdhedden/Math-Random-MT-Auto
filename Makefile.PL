use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Math::Random::MT::Auto',
    OBJECT            => 'MRMA.o',
    VERSION_FROM      => 'lib/Math/Random/MT/Auto.pm',
    PREREQ_PM         => { },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Math/Random/MT/Auto.pm',
       AUTHOR         => 'Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>') : ()),
);
