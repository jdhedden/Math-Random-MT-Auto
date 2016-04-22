# Module makefile for Math::Random::MT::Auto (using Module::Build)

use strict;
use warnings;
use Module::Build;


# Need to subclass Module::Build to handle ppport.h file
my $class = Module::Build->subclass(code => <<'EOF');
  # Copy the ppport.h file to where it will be expected under Module::Build
  sub ACTION_code {
    my $self = shift;
    my $ppp = 'ppport.h';
    my $lib_ppp = File::Spec->catfile('lib/Math/Random/MT', $ppp);
    $self->copy_if_modified(from => $ppp, to => $lib_ppp);
    $self->add_to_cleanup($lib_ppp);
    $self->SUPER::ACTION_code(@_);
  }
EOF


my $build = $class->new (
    module_name => 'Math::Random::MT::Auto',
    license => 'unrestricted',
    requires => {
                    'perl'         => '5.6.0',
                    'Scalar::Util' => '1.16',
                },

    # Module::Build doesn't check for ExtUtils::ParseXS, so we have to
    build_requires       => { 'ExtUtils::ParseXS' => 0, },
    xs_files             => { 'MRMA.xs' => 'lib/Math/Random/MT/Auto.xs', },
    # Module::Build doesn't generate VERSION/XS_VERSION, so we have to
    extra_compiler_flags => [ '-DVERSION="3.00.00"',
                              '-DXS_VERSION="3.00.00"' ],
);


# Check for C compiler
if (! $build->have_c_compiler()) {
    die("No 'C' compiler found to build Math::Random::MT::Auto\n");
}


$build->create_build_script;

# EOF
