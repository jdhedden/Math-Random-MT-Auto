# Module makefile for Math::Random::MT::Auto (using Module::Build)

use strict;
use warnings;
use Module::Build;

# First, check for C compiler
mkdir('_build', 0777);   # Workaround for bug in Module::Build
if (! Module::Build->new('module_name' => 'Math::Random::MT::Auto',
                         'license' => 'perl'
                        )->have_c_compiler())
{
    die("No 'C' compiler found to build Math::Random::MT::Auto\n");
}


# Need to subclass Module::Build to handle the 'ppport.h' file
my $mod_build = Module::Build->subclass(code => <<'EOF');
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

# Create make file
$mod_build->new(
    'module_name' => 'Math::Random::MT::Auto',
    'license'     => 'unrestricted',

    # Module::Build doesn't check for these, so we have to
    'build_requires' => {
                            'ExtUtils::CBuilder' => 0,
                            'ExtUtils::ParseXS'  => 0,
                        },

    'requires'       => {
                            'perl'         => '5.6.0',
                            'Scalar::Util' => '1.16'
                        },

    'xs_files' => { 'MRMA.xs' => 'lib/Math/Random/MT/Auto.xs' },

    # Module::Build doesn't generate VERSION/XS_VERSION, so we have to
    'extra_compiler_flags' => [ '-DVERSION="4.01.00"',
                                '-DXS_VERSION="4.01.00"' ]
)->create_build_script();

# EOF
