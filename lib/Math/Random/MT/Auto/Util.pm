use strict;
use warnings;

package Math::Random::MT::Auto::Util; {

our $VERSION = '4.13.00';

use Carp ();


### Module Initialization ###

# 1. Export our own version of Internals::SvREADONLY for Perl < 5.8
if (! UNIVERSAL::can('Internals', 'SvREADONLY')) {
    *Internals::SvREADONLY = \&Math::Random::MT::Auto::Util::SvREADONLY;
}


# 2. Export our subroutines
sub import
{
    my $class = shift;   # Not used

    # Export 'extract_args' by default
    my @EXPORT = (@_, 'extract_args');

    # Export subroutine names into the caller's namespace
    my $caller = caller();
    for my $sym (@EXPORT) {
        no strict 'refs';
        *{$caller.'::'.$sym} = \&{$sym};
    }
}


### Subroutines ###

=begin create_object

  my $ref = create_object($class);
  my $ref = create_object($class, $scalar);
  my $ref = create_object($class, $code_ref, ...);

This subroutine returns an object that consists of a reference to an anonymous
scalar that is blessed into the specified class.

The scalar is populated with a unique ID that can be used to reference the
object's attributes (this gives a preformance improvement over other ID
schemes).  For example,

  my $obj = create_object($class);
  $attribute{$$obj} = $value;

When called with just the $class argument, the referenced scalar is populated
with the address of the reference.

When called with an additional scalar argument, the referenced scalar will be
populated with the argument.

Finally, you can supply your own code for setting the object ID.  In this
case, provide a reference to the desired subroutine (or specify an anonymous
subroutine), followed by any arguments that it might need.  For example,

  my $obj = create_object($class, \&my_uniq_id, $arg1, $arg2);

If $class is undef, then an unblessed scalar reference is returned.

For safety, the value of the scalar is set to 'readonly'.

This subroutine will normally only be used in the object constructor of a base
classes (in this case 'Math::Random::MT::Auto').

=end create_object

=cut

sub create_object
{
    my ($class, $id, @args) = @_;

    # Create the object from an anonymous scalar reference
    my $obj = \(my $scalar);

    # Set the scalar equal to ...
    if (ref($id) eq 'CODE') {
        # ... the value returned by the user-specified subroutine
        $$obj = $id->(@args);

    } elsif (ref($id)) {
        # References not allowed
        Carp::croak('Usage: create_object($class, $scalar)');

    } elsif (defined($id)) {
        # ... the user-supplied scalar
        $$obj = $id;

    } else {
        # ... the address of the reference
        $$obj = 0+$obj;
    }

    # Bless the object into the specified class
    if ($class) {
        bless($obj, $class);
    }

    # Make the object 'readonly'
    Internals::SvREADONLY($$obj, 1);

    # Return the object
    return ($obj);
}


# Extracts wanted args from those given
sub extract_args
{
    my $wanted = shift;
    if (ref($wanted) ne 'HASH') {
        Carp::croak('Usage: extract_args({ ARG=>\'REGEX\', ... }, @_)');
    }

    # Gather arguments into a single hash ref
    my $args = {};
    while (my $arg = shift) {
        if (ref($arg) eq 'HASH') {
            # Add args from a hash ref
            @{$args}{keys(%{$arg})} = values(%{$arg});
        } elsif (ref($arg)) {
            Carp::croak("Bad initializer: @{[ref($arg)]} ref not allowed. (Must be 'key=>val' pair or hash ref.)");
        } elsif (! @_) {
            Carp::croak("Bad initializer: Missing value for key '$arg'. (Must be 'key=>val' pair or hash ref.)");
        } else {
            # Add 'key => value' pair
            $args->{$arg} = shift;
        }
    }

    # Search for wanted args
    my %found = ();
    EXTRACT: {
        # Try to match given argument keys against wanted keys
        PROCESS_ARG:
        for my $arg_key (keys(%{$args})) {
            for my $want_key (keys(%{$wanted})) {
                # Use either supplied regex or exact match on the key itself
                my $want_regex = ($wanted->{$want_key}) ? $wanted->{$want_key}
                                                        : "/^$want_key\$/";
                if (eval("'$arg_key' =~ $want_regex")) {
                    # Match - add arg to found hash
                    $found{$want_key} = $args->{$arg_key};
                    next PROCESS_ARG;   # Process next arg
                }
            }
        }

        # Check for class-specific argument hash ref
        if (exists($args->{my $class = caller()})) {
            $args = $args->{$class};
            if (ref($args) ne 'HASH') {
                Carp::croak("Class initializer for '$class' must be a hash ref");
            }
            # Loop back to process class-specific arguments
            redo EXTRACT;
        }
    }

    # Return found args
    return (%found);
}

} # End of lexical scope for package

1;

__END__

=head1 NAME

Math::Random::MT::Auto::Util - Utilities for Math::Random::MT::Auto subclasses

=head1 SYNOPSIS

    ### In Class ###

    use Math::Random::MT::Auto::Util;

    sub new
    {
        ...

        my %args = extract_args( {
                                    'PARAMS' => '/^(?:param|parm)s?$/i',
                                    'OPTION' => '/^(?:option|opt)$/i',
                                    'TYPE'   => '/^type$/i'
                                 },
                                 @_ );
        ...

        return ($self);
    }

    ### In Application ###

    my %initializers = (
          'Option' => 'filter',
          'Type'   => 'integer',
          'Math::Random::MT::Auto' => { 'Src' => 'dev_random' },
    );

    my $obj = My::Random->new(\%initializers,
                              'parms' => [ 4, 12 ]);


=head1 DESCRIPTION

This module provides utilities that support the inside-out object model used
by L<Math::Random::MT::Auto>.

=over

=item extract_args

    my %args = extract_args( { 'OPTION' => 'REGEX', ... }, @_ );

This subroutine provides a powerful and flexible mechanism for subclass
constructors to accept arguments from application code, and to extract the
arguments they need.  It processes the argument list sent to the constructor,
extracting arguments based on regular expressions, and returns a hash of the
matches.

The arguments are presented to the constructor in any combination of
C<key =E<gt> value> pairs and/or hash refs.  These are combined by
C<extract_args> into a single hash from which arguments are extracted, and
returned to the constructor.

Additionally, hash nesting is supported for providing class-specific
arguments.  For this feature, a key that is the name of a class is paired with
a hash reference containing arguments that are meant for that class's
constructor.

    my $obj = My::Class::Sub::Whatever->new(
                    'param'         => 'value',
                    'My::Class'     => {
                                            'param' => 'item',
                                       },
                    'My::Class:Sub' => {
                                            'param' => 'property',
                                       },
              );

In the above, class C<My::Class::Sub::Whatever> will get C<'param' =E<gt>
'value'>, C<My::Class::Sub> will get C<'param' =E<gt> 'property'>, and
C<My::Class> will get C<'param' =E<gt> 'item'>.

The first argument to C<extract_args> is a hash ref containing specifications
for the arguments to be extracted.  The keys in this hash will be the keys
in the returned hash for any extracted arguments.  The values are regular
expressions that are used to match the incoming argument keys.  If only an
exact match is desired, then the value for the key should be set to C<undef>.

=back

=head1 DIAGNOSTICS

=over

=item * Usage: extract_args({ ARG=>\'REGEX\', ... }, @_)

Your call to C<extract_args> did not have a hash ref as its first argument.

=item * Bad initializer: XXX ref not allowed. (Must be 'key=>val' pair or hash ref.)

=item * Bad initializer: Missing value for key 'XXX'. (Must be 'key=>val' pair or hash ref.)

=item * Class initializer for 'XXX' must be a hash ref

=back

=head1 SEE ALSO

Inside-out Object Model:
L<http://www.perlmonks.org/index.pl?node_id=219378>,
L<http://www.perlmonks.org/index.pl?node_id=483162>,
Chapter 15 of I<Perl Best Practices> by Damian Conway, and
L<Class::Std::Utils>

=head1 AUTHOR

Jerry D. Hedden, S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Jerry D. Hedden. All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
