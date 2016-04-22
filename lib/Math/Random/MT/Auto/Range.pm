package Math::Random::MT::Auto::Range;

use strict;
use warnings;
use Carp;
use Scalar::Util 1.16;

# Declare ourself as a subclass
use Math::Random::MT::Auto ':noauto';
our @ISA = qw(Math::Random::MT::Auto);

our $VERSION = '0.01.00';

# Set ID() as alias for refaddr() function
*ID = \&Scalar::Util::refaddr;


### Package Global Variables ###

# Object attribute hashes used by inside-out object model
#
# Data stored in these hashes is keyed to the object by a unique ID which is
# obtained using ID($obj).

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
            # Make allowances for user laziness
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

    # Obtain new object from parent class
    my $self;
    if (ref($thing)) {
        # $thing->new( ... ) was called
        # Therefore call parent class constructor using the 'parent' object
        $self = $thing->SUPER::new(%parent_args);
    } else {
        # SUBCLASS->new( ... ) was called
        # Therefore call parent class constructor directly
        $self = $ISA[0]->new(%parent_args);
    }

    # Re-bless object into specified class
    bless($self, $class);

    # The object's ID (refaddr()) is used as a hash key for the object
    my $id = ID($self);

    # Save weakened reference to object for thread cloning
    Scalar::Util::weaken($REGISTRY{$id} = $self);

    # Handle 'missing' arguments
    if (ref($thing)) {
        # $thing->new( ... ) was called
        # Copy 'missing' arguments from the 'parent' object
        my $thing_id = ID($thing);
        if (! exists($my_args{'TYPE'})) {
            $my_args{'TYPE'} = $TYPE{$thing_id};
        }
        if (! exists($my_args{'LOW'})) {
            $my_args{'LOW'} = $LOW{$thing_id};
        }
        if (! exists($my_args{'HIGH'})) {
            $my_args{'HIGH'} = $HIGH{$thing_id};
        }

    } else {
        # SUBCLASS->new( ... ) was called
        # 'LOW' and 'HIGH' are required
        if (! exists($my_args{'LOW'})) {
            croak('Missing parameter: LOW');
        }
        if (! exists($my_args{'HIGH'})) {
            croak('Missing parameter: HIGH');
        }
        # Default 'TYPE' to 'INTEGER' if 'LOW' and 'HIGH' are both integers
        if (! exists($my_args{'TYPE'})) {
            my $lo = $my_args{'LOW'};
            my $hi = $my_args{'HIGH'};
            $my_args{'TYPE'} = (($lo == int($lo)) && ($hi == int($hi)))
                             ? 'INTEGER'
                             : 'DOUBLE';
        }
    }

    # Perform subclass initialization
    $self->range_type($my_args{'TYPE'});
    $self->range($my_args{'LOW'}, $my_args{'HIGH'});

    # Done - return object
    return ($self);
}


# Return current range type
# If called with an argument, sets the type accordingly
sub range_type
{
    my $self = shift;
    my $id = ID($self);

    # Set/change the type
    if (@_) {
        $TYPE{$id} = ($_[0] =~ /^I/i) ? 'INTEGER' : 'DOUBLE';
    }

    # Return the current range type
    return ($TYPE{$id});
}


# Return current number range
# If called with arguments, sets the range accordingly
sub range
{
    my $self = shift;
    my $id = ID($self);

    # Set/change the range
    if (@_) {
        my ($lo, $hi) = @_;
        if (! defined($hi)) {
            croak('Usage: $obj->range($lo, $hi)');
        }

        # Ensure arguments are of the proper type
        if ($TYPE{$id} eq 'INTEGER') {
            $lo = int($lo);
            $hi = int($hi);
        } else {
            $lo = 0.0 + $lo;
            $hi = 0.0 + $hi;
        }
        # Make sure 'LOW' and 'HIGH' are not the same
        if ($lo == $hi) {
            croak('Invalid arguments: LOW and HIGH are equal');
        }
        # Ensure LOW < HIGH
        if ($lo > $hi) {
            ($lo, $hi) = ($hi, $lo);
        }

        # Set range parameters
        $LOW{$id}  = $lo;
        $HIGH{$id} = $hi;
        if ($TYPE{$id} eq 'INTEGER') {
            $RANGE{$id} = ($HIGH{$id} - $LOW{$id}) + 1;
        } else {
            $RANGE{$id} = $HIGH{$id} - $LOW{$id};
        }
    }

    # Return the current range values
    return ($LOW{$id}, $HIGH{$id});
}


# Return a random number of the configured type and within the configured
# range.
sub rrand
{
    my $self = $_[0];
    my $id = ID($self);

    if ($TYPE{$id} eq 'INTEGER') {
        # Integer random number range [LOW, HIGH]
        return (($self->irand() % $RANGE{$id}) + $LOW{$id});
    } else {
        # Floating-point random number range [LOW, HIGH)
        return ($self->rand($RANGE{$id}) + $LOW{$id});
    }
}


# Object Destructor
sub DESTROY {
    my $self = $_[0];
    my $id = ID($self);

    # Call parent's destructor first
    $self->SUPER::DESTROY();

    # Delete all subclass data used for the object
    delete($TYPE{$id});
    delete($LOW{$id});
    delete($HIGH{$id});
    delete($RANGE{$id});

    # Remove object from thread cloning registry
    delete($REGISTRY{$id});
}


### Thread Cloning Support ###

# Called after thread is cloned
sub CLONE
{
    # Don't execute when called for sub-classes
    if ($_[0] eq __PACKAGE__) {
        # Process each cloned object
        for my $old_id (keys(%REGISTRY)) {
            # Get cloned object associated with old ID
            my $obj = delete($REGISTRY{$old_id});

            # New ID for referencing the cloned object
            my $new_id = ID($obj);

            # Relocate object data
            $TYPE{$new_id}  = delete($TYPE{$old_id});
            $LOW{$new_id}   = delete($LOW{$old_id});
            $HIGH{$new_id}  = delete($HIGH{$old_id});
            $RANGE{$new_id} = delete($RANGE{$old_id});

            # Save weak reference to this cloned object
            Scalar::Util::weaken($REGISTRY{$new_id} = $obj);
        }
    }
}

1;

__END__

=head1 NAME

Math::Random::MT::Auto::Range - Range-valued PRNGs

=head1 SYNOPSIS

  use strict;
  use warnings;
  use Math::Random::MT::Auto::Range;

  # Integer random number range
  my $die = Math::Random::MT::Auto::Range(LO => 1, HI => 6);
  my $roll = $die->rrand();

  # Floating-point random number range
  my $compass = Math::Random::MT::Auto::Range(LO => 0, HI => 360,
                                              TYPE => 'DOUBLE');
  my $course = $compass->rrand();

=head1 DESCRIPTION

This module creates range-valued pseudo-random number generators (PRNGs) which
return random values between two specified limits.

While useful in itself, the primary purpose of this module is to provide an
example of how to create subclasses of Math::Random::MT::Auto.

=head1 USAGE

=over

=item Module Declaration

This module does not export any functions or symbols.

  use strict;
  use warnings;
  use Math::Random::MT::Auto::Range;

=item Math::Random::MT::Auto::Range->new

Creates a new range-valued PRNG.

  my $prng = Math::Random::MT::Auto::Range->new( %options );

Available options are:

=over

=item 'LOW' => $num

=item 'HIGH' => $num

Sets the limits over which the values return by the PRNG will range.  If the
C<TYPE> for the PRNG is C<INTEGER>, then the range will be C<LOW> to C<HIGH>
inclusive (i.e., [LOW, HIGH]).  If C<DOUBLE>, then C<LOW> inclusive to C<HIGH>
exclusive (i.e., [LOW, HIGH)).

C<LOW> and C<HIGH> must be specified when calling C<new> as a class method.

=item 'TYPE' => 'INTEGER'

=item 'TYPE' => 'DOUBLE'

Sets the type for the values returned from the PRNG.  If C<TYPE> is not
specified, it will default to C<INTEGER> if both C<LOW> and C<HIGH> are
integers.

=back

=item $obj->new

Creates a new PRNG, using any specified options, and then using attributes
from the referenced PRNG.

  my $prng2 = $prng1->new( %options );

With no options, the new PRNG will be a complete clone of the referenced
PRNG.

=item $obj->range

Returns a list of the PRNG's range limits.

  my ($lo, $hi) = $prng->range();

If called with arguments, it sets the limits for the PRNG's return value
range.

  $prng->range($lo, $hi);

=item $obj->range_type

Returns the type for the return values from the PRNG.

  my $type = $prng->range_type();

If called with an argument, it sets the PRNG's type.

  $prng->range_type('INTEGER');
  $prng->range_type('DOUBLE');

=item $obj->rrand

Returns a random number of the configured type within the configured range.

  my $rand = $prng->rrand();

If the C<TYPE> for the PRNG is C<INTEGER>, then the range will be C<LOW> to
C<HIGH> inclusive (i.e., [LOW, HIGH]).  If C<DOUBLE>, then C<LOW> inclusive to
C<HIGH> exclusive (i.e., [LOW, HIGH)).

=back

=head1 SEE ALSO

L<Math::Random::MT::Auto>

=head1 AUTHOR

Jerry D. Hedden, S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Jerry D. Hedden. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
