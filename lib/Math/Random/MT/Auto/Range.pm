package Math::Random::MT::Auto::Range; {

use strict;
use warnings;
use Carp ();
use Scalar::Util 1.16 qw(weaken looks_like_number);

# Declare ourself as a subclass
use base 'Math::Random::MT::Auto';

our $VERSION = '4.08.00';


### Package Global Variables ###

# Object attribute hashes used by inside-out object model
#
# Data stored in these hashes is keyed to the object by a unique ID that is
# stored in the object's scalar reference.

# Range information for our objects
my %TYPE;       # Type of range:  INTEGER or DOUBLE
my %LOW;        # Low end of the range
my %HIGH;       # High end of the range
my %RANGE;      # 'Difference' between LOW and HIGH
                #   (used for performance considerations)

# Maintains weak references to objects for thread cloning
my %REGISTRY;


### Object Methods ###

# Constructor - creates a new object
sub new
{
    my $thing = shift;
    my $class = ref($thing) || $thing;

    # Separate '@_' into args for this subclass and args for parent class
    # Best practices call for all args to come in 'pairs'
    #   (i.e., 'name' => 'value'), so they can be accessed via hashes.
    my (%my_args, %parent_args);
    while (my $arg = shift) {
        # Only the 'TYPE', 'LOW' and 'HIGH' args are for this subclass
        if ($arg =~ /^(TYPE|LO(W)?|HI(GH)?)$/i) {
            # Allow synonyms
            $arg = uc($arg);
            if ($arg eq 'LO') {
                $arg = 'LOW'
            }
            if ($arg eq 'HI') {
                $arg = 'HIGH'
            }
            $my_args{$arg} = shift;
        } else {
            # All other args will be passed to the parent class
            $parent_args{$arg} = shift;
        }
    }

    # Check arguments
    # 'LOW' and 'HIGH' are required
    if (! exists($my_args{'LOW'})) {
        Carp::croak('Missing parameter: LOW');
    }
    if (! exists($my_args{'HIGH'})) {
        Carp::croak('Missing parameter: HIGH');
    }

    # Default 'TYPE' to 'INTEGER' if 'LOW' and 'HIGH' are both integers
    if (! exists($my_args{'TYPE'})) {
        my $lo = $my_args{'LOW'};
        my $hi = $my_args{'HIGH'};
        $my_args{'TYPE'} = (($lo == int($lo)) && ($hi == int($hi)))
                         ? 'INTEGER'
                         : 'DOUBLE';
    }

    # Obtain new object from parent class
    my $self = __PACKAGE__->SUPER::new(%parent_args);

    # Rebless object into specified class
    # 'bless()' cannot be used because the object
    #   is set to 'readonly' by ->new()
    $self->_rebless($class);

    # Save weakened reference to object for thread cloning
    weaken($REGISTRY{$$self} = $self);

    # Perform subclass initialization
    $self->set_range_type($my_args{'TYPE'});
    $self->set_range($my_args{'LOW'}, $my_args{'HIGH'});

    # Done - return object
    return ($self);
}


# Creates a copy of a PRNG object
sub clone
{
    my $parent = shift;

    # Call parent class 'clone' method
    my $self = $parent->SUPER::clone();

    # Save weakened reference to object for thread cloning
    weaken($REGISTRY{$$self} = $self);

    # Perform subclass initialization using parent's properties
    $self->set_range_type($parent->get_range_type());
    $self->set_range($parent->get_range());

    # Done - return object
    return ($self);
}


# Sets numeric type random values
sub set_range_type
{
    my $self = shift;

    # Check argument
    my $type = $_[0];
    if (! defined($type) || $type !~ /^[ID]/i) {
        Carp::croak('Arg to ->set_range_type() must be \'INTEGER\' or \'DOUBLE\'');
    }

    $TYPE{$$self} = ($type =~ /^I/i) ? 'INTEGER' : 'DOUBLE';
}


# Return current range type
sub get_range_type
{
    my $self = shift;
    return ($TYPE{$$self});
}


# Set random number range
sub set_range
{
    my $self = shift;

    # Check for arguments
    my ($lo, $hi) = @_;
    if (! looks_like_number($lo) || ! looks_like_number($hi)) {
        Carp::croak('->range() requires two numeric args');
    }

    # Ensure arguments are of the proper type
    if ($TYPE{$$self} eq 'INTEGER') {
        $lo = int($lo);
        $hi = int($hi);
    } else {
        $lo = 0.0 + $lo;
        $hi = 0.0 + $hi;
    }
    # Make sure 'LOW' and 'HIGH' are not the same
    if ($lo == $hi) {
        Carp::croak('Invalid arguments: LOW and HIGH are equal');
    }
    # Ensure LOW < HIGH
    if ($lo > $hi) {
        ($lo, $hi) = ($hi, $lo);
    }

    # Set range parameters
    $LOW{$$self}  = $lo;
    $HIGH{$$self} = $hi;
    if ($TYPE{$$self} eq 'INTEGER') {
        $RANGE{$$self} = ($HIGH{$$self} - $LOW{$$self}) + 1;
    } else {
        $RANGE{$$self} = $HIGH{$$self} - $LOW{$$self};
    }
}


# Return object's random number range
sub get_range
{
    my $self = shift;
    return ($LOW{$$self}, $HIGH{$$self});
}


# Return a random number of the configured type and within the configured
# range.
sub rrand
{
    my $self = $_[0];

    if ($TYPE{$$self} eq 'INTEGER') {
        # Integer random number range [LOW, HIGH]
        return (($self->irand() % $RANGE{$$self}) + $LOW{$$self});
    } else {
        # Floating-point random number range [LOW, HIGH)
        return ($self->rand($RANGE{$$self}) + $LOW{$$self});
    }
}


# Object Destructor
sub DESTROY {
    my $self = $_[0];

    # Call parent's destructor first
    $self->SUPER::DESTROY();

    # Delete all subclass data used for the object
    delete($TYPE{$$self});
    delete($LOW{$$self});
    delete($HIGH{$$self});
    delete($RANGE{$$self});

    # Remove object from thread cloning registry
    delete($REGISTRY{$$self});
}


### Thread Cloning Support ###

# Called after thread is cloned
sub CLONE
{
    # Don't execute when called for sub-classes
    if ($_[0] eq __PACKAGE__) {
        # Process each object in the registry
        for my $old_id (keys(%REGISTRY)) {
            # Get cloned object associated with old ID
            my $obj = delete($REGISTRY{$old_id});

            # Relocate object data
            $TYPE{$$obj}  = delete($TYPE{$old_id});
            $LOW{$$obj}   = delete($LOW{$old_id});
            $HIGH{$$obj}  = delete($HIGH{$old_id});
            $RANGE{$$obj} = delete($RANGE{$old_id});

            # Save weak reference to this cloned object
            weaken($REGISTRY{$$obj} = $obj);
        }
    }
}

} # End of package lexical scope

1;

__END__

=head1 NAME

Math::Random::MT::Auto::Range - Range-valued PRNGs

=head1 SYNOPSIS

  use strict;
  use warnings;
  use Math::Random::MT::Auto::Range;

  # Integer random number range
  my $die = Math::Random::MT::Auto::Range->new(LO => 1, HI => 6);
  my $roll = $die->rrand();

  # Floating-point random number range
  my $compass = Math::Random::MT::Auto::Range->new(LO => 0, HI => 360,
                                                   TYPE => 'DOUBLE');
  my $course = $compass->rrand();

=head1 DESCRIPTION

This module creates range-valued pseudorandom number generators (PRNGs) that
return random values between two specified limits.

While useful in itself, the primary purpose of this module is to provide an
example of how to create subclasses of Math::Random::MT::Auto within the
inside-out object model.

=head1 MODULE DECLARATION

Add the following to the top of our application code:

  use strict;
  use warnings;
  use Math::Random::MT::Auto::Range;

This module is strictly OO, and does not export any functions or symbols.

=head1 METHODS

=over

=item Math::Random::MT::Auto::Range->new

Creates a new range-valued PRNG.

  my $prng = Math::Random::MT::Auto::Range->new( %options );

Available options are:

=over

=item 'LOW' => $num

=item 'HIGH' => $num

Sets the limits over which the values return by the PRNG will range.  These
arguments are mandatory, and C<LOW> must not be equal to C<HIGH>.

If the C<TYPE> for the PRNG is C<INTEGER>, then the range will be C<LOW> to
C<HIGH> inclusive (i.e., [LOW, HIGH]).  If C<DOUBLE>, then C<LOW> inclusive to
C<HIGH> exclusive (i.e., [LOW, HIGH)).

C<LO> and C<HI> can be used as synonyms for C<LOW> and C<HIGH>, respectively.

=item 'TYPE' => 'INTEGER'

=item 'TYPE' => 'DOUBLE'

Sets the type for the values returned from the PRNG.  If C<TYPE> is not
specified, it will default to C<INTEGER> if both C<LOW> and C<HIGH> are
integers.

=back

The options above are also supported using lowercase and mixed-case (e.g.,
'low', 'hi', 'Type', etc.).

Additionally, objects created with this package can take any of the options
supported by the L<Math::Random::MT::Auto> class, namely, C<STATE>, C<SEED>
and C<STATE>.

=item $obj->new

Creates a new PRNG in the same manner as
L</"Math::Random::MT::Auto::Range-E<gt>new">.

  my $prng2 = $prng1->new( %options );

=item $obj->clone

Creates a new PRNG that is a copy of the referenced PRNG.

  my $prng2 = $prng1->clone();

=back

In addition to the methods describe below, the objects created by this package
also support all the object methods provided by the L<Math::Random::MT::Auto>
class.

=over

=item $obj->rrand

Returns a random number of the configured type within the configured range.

  my $rand = $prng->rrand();

If the C<TYPE> for the PRNG is C<INTEGER>, then the range will be C<LOW> to
C<HIGH> inclusive (i.e., [LOW, HIGH]).  If C<DOUBLE>, then C<LOW> inclusive to
C<HIGH> exclusive (i.e., [LOW, HIGH)).

=item $obj->set_range_type

Sets the numeric type for the random numbers returned by the PRNG.

  $prng->set_range_type('INTEGER');
    # or
  $prng->set_range_type('DOUBLE');

=item $obj->get_range_type

Returns the numeric type ('INTEGER' or 'DOUBLE') for the random numbers
returned by the PRNG.

  my $type = $prng->get_range_type();

=item $obj->set_range

Sets the limits for the PRNG's return value range.

  $prng->set_range($lo, $hi);

C<$lo> must not be equal to C<$hi>.

=item $obj->get_range

Returns a list of the PRNG's range limits.

  my ($lo, $hi) = $prng->get_range();

=back

=head1 DIAGNOSTICS

=over

=item * Missing parameter: LOW

=item * Missing parameter: HIGH

The L<LOW and HIGH|/"'LOW' =E<gt> $num"> values for the range must be
specified to L<-E<gt>new()|/"Math::Random::MT::Auto::Range-E<gt>new">.

=item * Arg to ->set_range_type() must be 'INTEGER' or 'DOUBLE'

Self explanatory.

=item * ->range() requires two numeric args

Self explanatory.

=item * Invalid arguments: LOW and HIGH are equal

You cannot specify a range of zero width.

=back

This module will reverse the range limits if they are specified in the
wrong order (i.e., it makes sure that C<LOW < HIGH>).

=head1 SEE ALSO

L<Math::Random::MT::Auto>

=head1 AUTHOR

Jerry D. Hedden, S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Jerry D. Hedden. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
