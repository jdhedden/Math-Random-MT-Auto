# Tests the Math::Random::MT::Auto::Util

use strict;
use warnings;
use Scalar::Util 1.10 qw(looks_like_number);

use Test::More tests => 34;

BEGIN {
    use_ok('Math::Random::MT::Auto');
    use_ok('Math::Random::MT::Auto::Util', qw(create_object));
}

### Test 'readonly'

my $scal = 1;
my $scal_ref = \$scal;
Math::Random::MT::Auto::Util::SvREADONLY($scal, 1);
eval { $$scal_ref = 2; };
ok($@, "Readonly: $@");
Math::Random::MT::Auto::Util::SvREADONLY($scal, 0);
eval { $$scal_ref = 2; };
ok(! $@, "Mutable: $@");
ok($scal == 2, "Changed to 2: $scal");
Math::Random::MT::Auto::Util::SvREADONLY($$scal_ref, 1);
eval { $scal = 1; };
ok($@, "Readonly: $@");


### Test create_object()

my $obj = create_object('TEST', sub { return($_[0]); }, 99);
isa_ok($obj, 'TEST');
ok($$obj == 99, "Scalar value: $$obj");
eval{
    my $old = $$obj;
    $$obj = 42;
    $$obj = $old;   # Just in case
};
ok($@, "Readonly: $@");

$obj = create_object('TEST');
isa_ok($obj, 'TEST');
ok(looks_like_number($$obj), "Scalar value: $$obj");

$obj = create_object('TEST', 12);
isa_ok($obj, 'TEST');
ok($$obj == 12, "Scalar value: $$obj");

$obj = create_object('TEST', 'test');
isa_ok($obj, 'TEST');
ok($$obj eq 'test', "Scalar value: $$obj");

eval { $obj = create_object('TEST', { 'test' => 1 }); };
ok($@, "Bad arg: $@");

$obj = create_object();
ok(ref($obj) eq 'SCALAR', 'Scalar ref');
ok(looks_like_number($$obj), "Scalar value: $$obj");
eval{
    my $old = $$obj;
    $$obj = 123;
    $$obj = $old;   # Just in case
};
ok($@, "Readonly: $@");

$obj = create_object(undef, 42);
ok(ref($obj) eq 'SCALAR', 'Scalar ref');
ok($$obj == 42, "Scalar value: $$obj");

$obj = create_object('', sub { return($_[0]); }, 99);
ok(ref($obj) eq 'SCALAR', 'Scalar ref');
ok(looks_like_number($$obj), "Scalar value: $$obj");

### Test extract_args()

my %wanted = (
    'TYPE'   => '/^type$/i',
    'CODE'   => '/^c(?:ode)?$/i',
    'SOURCE' => '/^(?:source|src)$/i',
    'IGNORE' => '/^(?:Ignore|Ign)$/',
);

my %args = (
    'type' => 'Check',
    'c'    => 'Strict',
    'Src'  => 'Internet',
    'main' => {
                'Code'   => 'Warning',
                'Ignore' => 'Not Used',
                'Source' => 'File',
              },

);

my %result = (
    'TYPE'   => 'Check',
    'CODE'   => 'Warning',
    'SOURCE' => 'File',
    'IGNORE' => 'Not Used',
);

my %found;

eval { %found = extract_args('test' => 'Check'); };
ok($@, "{wanted} missing: $@");
undef(%found);

%found = extract_args(\%wanted, 'test' => 'Check');
ok(! %found, 'key=>value not matched');
undef(%found);

%found = extract_args(\%wanted, 'Type' => 'Check');
is_deeply(\%found, { 'TYPE' => 'Check' }, 'key=>value matched');
undef(%found);

%found = extract_args({ 'TYPE' => '' }, 'Type' => 'Check');
ok(! %found, 'Exact key=>value not matched');
undef(%found);

%found = extract_args({ 'TYPE' => '' }, 'TYPE' => 'Check');
is_deeply(\%found, { 'TYPE' => 'Check' }, 'Exact key=>value matched');
undef(%found);

%found = extract_args(\%wanted, \%args);
is_deeply(\%found, \%result, 'Hash ref');
undef(%found);

$args{'main'} = 'test';
eval { %found = extract_args(\%wanted, \%args); };
ok($@, "Init not hash ref: $@");
undef(%found);

package My::Test; {
    use Math::Random::MT::Auto::Util;
    use Test::More;

    my %arg2 = (
        'My::Test' => {
                        'c'   => 'Bogus',
                      },
    );

    my %result = (
        'TYPE'   => 'Check',
        'CODE'   => 'Bogus',
        'SOURCE' => 'Internet',
    );

    %found = extract_args(\%wanted, \%args, \%arg2);
    is_deeply(\%found, \%result, '2 Hash refs');
    undef(%found);

    %found = extract_args(\%wanted, \%args, 'Ign' => 'Silent', \%arg2);
    $result{'IGNORE'} = 'Silent';
    is_deeply(\%found, \%result, 'Hash refs + key=>pair');
    undef(%found);

    eval { %found = extract_args(\%wanted, \%args, \%arg2, 'Key'); };
    ok($@, "Arg missing: $@");
    undef(%found);

    eval { %found = extract_args(\%wanted, \%args, \%arg2, [ 'key' ]); };
    ok($@, "Non-hash ref: $@");
    undef(%found);
}

# EOF
