use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Math::Random::MT::Net',
    OBJECT            => 'Net.o mt19937ar.o',
    VERSION_FROM      => 'lib/Math/Random/MT/Net.pm',
    PREREQ_PM         => { LWP::UserAgent   => 2.0 },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Math/Random/MT/Net.pm',
       AUTHOR         => 'Jerry D. Hedden <jdhedden@1979.usna.com>') : ()),
);
