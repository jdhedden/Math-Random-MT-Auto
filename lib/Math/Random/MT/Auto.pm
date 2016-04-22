require 5.006;

use strict;
use warnings;

package Math::Random::MT::Auto; {

our $VERSION = '4.10.00';

use Carp ();
use Scalar::Util qw(blessed looks_like_number weaken);

use base 'DynaLoader';
bootstrap Math::Random::MT::Auto $VERSION;

require Math::Random::MT::Auto::Util;
import Math::Random::MT::Auto::Util qw(create_object);


### Inside-out Object Model Support ###

# Maintains references to all object attribute hashes (including those in
# subclasses) for easy manipulation of attribute data during global object
# actions (e.g., cloning, destruction).
my @FIELDS;

# This attribute handler adds the references for object attribute hashes (in
# both this class and any subclasses) to the attribute registry '@FIELDS'
# above.  These hashes are marked with an attribute called 'Field'.  See
# 'perldoc attributes' for details.
sub MODIFY_HASH_ATTRIBUTES
{
    my ($package, $var_ref, @attrs) = @_;

    # Add hash reference to the attribute registry
    # if marked with the 'Field' attribute
    if (grep { $_ eq 'Field' } @attrs) {
        push(@FIELDS, $var_ref);
    }

    # Return any unused attributes
    return (grep { $_ ne 'Field' } @attrs);
}

# Maintains weak references to PRNG objects for thread cloning
my %OBJECTS;


### Inside-out Object Attributes ###

# Object data is stored in these attribute hashes, and is keyed to the object
# by a unique ID that is stored in the object's scalar reference.  For this
# class, that ID is the address of the PRNG's internal memory.
#
# These hashes are declared using the attribute called 'Field'.

my %sources_for : Field;   # Sources from which to obtain random seed data
my %seed_for    : Field;   # Last seed sent to the PRNG


### Standalone PRNG pseudo-object
#
# The standalone PRNG is treated, in some respects, like a PRNG object.  For
# example, its attributes are stored in the object attribute hashes, but it is
# not added to the cloning registry.  This approach allows certain subroutines
# to operate both as object methods and as the functional interface to the
# standalone PRNG.
my $SA;


### Forward Declarations for Internal Subroutines ###
#
# Refs to anonymous internal subroutines.  This approach hides them from the
# outside world.
my $acq_seed;     # Acquires seed data for a PRNG


### Module Initialization ###

# 1. Export our own version of Internals::SvREADONLY for Perl < 5.8
if (! UNIVERSAL::can('Internals', 'SvREADONLY')) {
    *Internals::SvREADONLY = \&Math::Random::MT::Auto::Util::SvREADONLY;
}


# 2. Initialize the standalone PRNG
#
# Set up the standalone PRNG pseudo-object with a
# ref to a pointer to the PRNG's internal memory
$SA = create_object(undef, \&Math::Random::MT::Auto::_::sa_prng);
# The standalone PRNG's sources will be set up in import(), and will
# be used as the default sources for any objects that are created
$sources_for{$$SA} = [];
# The seed is set up in import()
$seed_for{$$SA}    = [];


# 3. Handle exportation of subroutine names,
# user-specified and default seeding sources,
# and auto-seeding of the standalone PRNG.
sub import
{
    my $class = shift;   # Not used

    # Exportable subroutines
    my %EXPORT_OK;
    @EXPORT_OK{qw(rand irand shuffle gaussian
                  exponential erlang poisson binomial
                  srand get_seed set_seed get_state set_state)} = undef;

    my $auto_seed = 1;   # Flag for auto-seeding standalone PRNG

    # Handle entries in the import list
    my $caller = caller();
    while (my $sym = shift) {
        if (exists($EXPORT_OK{lc($sym)})) {
            # Export subroutine names
            no strict 'refs';
            $sym = lc($sym);
            *{$caller.'::'.$sym} = \&{$sym};

        } elsif ($sym =~ /^:(no|!)?auto$/i) {
            # To auto-seed (:auto is default) or not (:!auto or :noauto)
            $auto_seed = not defined($1);

        } else {
            # User-specified seed acquisition sources
            # or user-defined seed acquisition subroutines
            push(@{$sources_for{$$SA}}, $sym);
            # Add max. source count, if specified
            if (@_ && looks_like_number($_[0])) {
                push(@{$sources_for{$$SA}}, shift);
            }
        }
    }

    # Set up default seed sources, if none specified by user
    if (! @{$sources_for{$$SA}}) {
        if ($^O eq 'MSWin32') {
            my ($id, $major, $minor) = (Win32::GetOSVersion())[4,1,2];
            if (defined($minor) &&
                (($id > 2) ||
                 ($id == 2 && $major > 5) ||
                 ($id == 2 && $major == 5 && $minor >= 1)))
            {
                push(@{$sources_for{$$SA}}, 'win32');
            }

        } elsif (-e '/dev/urandom') {
            push(@{$sources_for{$$SA}}, '/dev/urandom');

        } elsif (-e '/dev/random') {
            push(@{$sources_for{$$SA}}, '/dev/random');
        }
        push(@{$sources_for{$$SA}}, 'random_org');
    }

    # Auto-seed the standalone PRNG
    if ($auto_seed) {
        # Automatically acquire seed from sources for standalone PRNG
        &$acq_seed($SA);

    } else {
        # Minimal seed when ':!auto' specified
        push(@{$seed_for{$$SA}}, $$, time(), $$SA);
    }
    # Apply seed
    Math::Random::MT::Auto::_::seed_prng($SA, $seed_for{$$SA});
}


### Thread Cloning Support ###

# Called after thread is cloned.  Handles data for subclasses, too.
sub CLONE
{
    # Don't execute when called for subclasses
    if ($_[0] eq __PACKAGE__) {
        # Process each object in the registry
        for my $old_id (keys(%OBJECTS)) {
            # Get cloned object associated with old ID
            my $obj = delete($OBJECTS{$old_id});

            # Get current state from parent PRNG's memory
            # which is currently shared
            my $state = $obj->get_state();

            # Unlock the object
            Internals::SvREADONLY($$obj, 0);
            # Create new memory for this cloned PRNG object
            $$obj = Math::Random::MT::Auto::_::new_prng();
            # Lock the object again
            Internals::SvREADONLY($$obj, 1);

            # Set state for this cloned PRNG object
            $obj->set_state($state);

            # Update the keys of the attribute hashes with the new object ID.
            # Handles attributes in subclasses, too.
            for (@FIELDS) {
                $_->{$$obj} = delete($_->{$old_id});
            }

            # Resave weakened reference to object
            weaken($OBJECTS{$$obj} = $obj);
        }
    }
}


### Dual-Interface (Functional and OO) Subroutines ###
#
# The subroutines below work both as regular 'functions' for the functional
# interface to the standalone PRNG, as well as methods for the OO interface
# to PRNG objects.

# Starts PRNG with random seed using specified sources (if any)
sub srand
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    if (@_) {
        # If sent seed by mistake, then send it to set_seed()
        if (looks_like_number($_[0]) || ref($_[0]) eq 'ARRAY') {
            if (blessed($obj)) {
                $obj->set_seed(@_);
            } else {
                set_seed(@_);
            }
            return;
        }

        # Save specified sources
        @{$sources_for{$$obj}} = @_;
    }

    # Acquire seed from sources
    &$acq_seed($obj);

    # Seed the PRNG
    Math::Random::MT::Auto::_::seed_prng($obj, $seed_for{$$obj});
}


# Return ref to PRNG's saved seed (if any)
sub get_seed
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    return ($seed_for{$$obj});
}


# Apply supplied seed, if given, to the PRNG,
sub set_seed
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    # Check argument
    if (! @_) {
        Carp::croak('Missing argument to \'set_seed\'');
    }

    # Save a copy of the seed
    if (ref($_[0]) eq 'ARRAY') {
        @{$seed_for{$$obj}} = @{$_[0]};
    } else {
        @{$seed_for{$$obj}} = @_;
    }

    # Seed the PRNG
    Math::Random::MT::Auto::_::seed_prng($obj, $seed_for{$$obj});
}


# Return copy of PRNG's current state
sub get_state
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    return (Math::Random::MT::Auto::_::get_state($obj));
}


# Set PRNG to supplied state
sub set_state
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    # Check argument
    my $state = $_[0];
    if (ref($state) ne 'ARRAY') {
        Carp::croak('\'set_state\' requires an array ref');
    }

    Math::Random::MT::Auto::_::set_state($obj, $state);
}


### Object Methods ###

# Object Constructor - creates a new PRNG object
sub new
{
    my $thing = shift;
    my $class = ref($thing) || $thing;

    ### Extract arguments needed by this class

    my %args = extract_args( {
                                'SOURCE' => '/^(?:source|src)s?$/i',
                                'SEED'   => '/^seed$/i',
                                'STATE'  => '/^state$/i'
                             },
                             @_ );

    ### Validate arguments and/or add defaults

    # Make sure state is an array ref
    if (exists($args{'STATE'}) && (ref($args{'STATE'}) ne 'ARRAY')) {
        Carp::croak('Invalid argument to ' . __PACKAGE__ .
                        '->new(): Value for \'STATE\' is not an array ref');
    }

    ### Create object

    # Create a new object using ref to a pointer to the PRNG's internal memory
    my $self = create_object($class, \&Math::Random::MT::Auto::_::new_prng);

    # Save weakened reference to object for thread cloning
    weaken($OBJECTS{$$self} = $self);

    ### Initialize object

    # User-specified sources
    if (exists($args{'SOURCE'})) {
        my $src = $args{'SOURCE'};
        # Make sure source is saved as an array ref
        $sources_for{$$self} = (ref($src) eq 'ARRAY') ? $src : [ $src ];

    } else {
        # If no sources specified, then use
        # default sources from standalone PRNG
        @{$sources_for{$$self}} = @{$sources_for{$$SA}};
    }

    # User-specified seed
    if (exists($args{'SEED'})) {
        my $seed = $args{'SEED'};
        # Make sure seed is saved as an array ref
        $seed_for{$$self} = (ref($seed) eq 'ARRAY') ? $seed : [ $seed ];

    } else {
        # No seed just yet
        $seed_for{$$self} = [];
    }

    # If state is specified, then use it
    if (exists($args{'STATE'})) {
        $self->set_state($args{'STATE'});

    } else {
        # Acquire seed, if none provided
        if (! @{$seed_for{$$self}}) {
            &$acq_seed($self);
        }

        # Seed the PRNG
        Math::Random::MT::Auto::_::seed_prng($self, $seed_for{$$self});
    }

    ### Done - return object
    return ($self);
}


# Creates a copy of a PRNG object
# This method is inherited by subclasses
sub clone
{
    my $parent = shift;
    my $class  = ref($parent);

    # Create a new object using ref to a pointer to the PRNG's internal memory
    my $clone = create_object($class, \&Math::Random::MT::Auto::_::new_prng);

    # Clone the state from the parent object
    $clone->set_state($parent->get_state());

    # Clone attributes from the parent.
    # Handles attributes in subclasses, too.
    for (@FIELDS) {
        $_->{$$clone} = $_->{$$parent};
    }

    # Save weakened reference to clone for any further thread cloning
    weaken($OBJECTS{$$clone} = $clone);

    # Done - return clone
    return ($clone);
}


# Object Destructor
# This 'method' is inherited by subclasses
sub DESTROY {
    my $self = $_[0];

    if ($$self) {
        # Delete the object from the attribute hashes.
        # Handles attributes in subclasses, too.
        for (@FIELDS) {
            delete($_->{$$self});
        }

        # Delete the object from the thread cloning registry
        delete($OBJECTS{$$self});

        # Free the internal memory used by the PRNG
        Math::Random::MT::Auto::_::free_prng($self);
        # Unlock the object
        Internals::SvREADONLY($$self, 0);
        # Erase the object ID
        $$self = undef;
    }
}


### Internal Subroutines ###
#
# Anonymous subroutine refs are used to hide internal functionality from the
# outside world.

use Config ();

### Constants

# Size of Perl's integers (32- or 64-bit) and corresponding unpack code
my $INT_SIZE    = $Config::Config{'uvsize'};
my $UNPACK_CODE = ($INT_SIZE == 8) ? 'Q' : 'L';
# Number of ints for a full 19968-bit seed
my $FULL_SEED   = 2496 / $INT_SIZE;


# Acquire seed data from a device/file
my $_src_device = sub {
    my $device = $_[0];
    my $prng   = $_[1];
    my $need   = $_[2];
    my $bytes  = $need * $INT_SIZE;

    # Try opening device/file
    my $FH;
    if (! open($FH, '<', $device)) {
        Carp::carp("Failure opening random device '$device': $!");
        return;
    }
    binmode($FH);

    # Try to set non-blocking mode (but not on Windows)
    if ($^O ne 'MSWin32') {
        eval {
            require Fcntl;

            my $flags;
            $flags = fcntl($FH, &Fcntl::F_GETFL, 0)
                or die("Failed getting filehandle flags: $!\n");
            fcntl($FH, &Fcntl::F_SETFL, $flags | &Fcntl::O_NONBLOCK)
                or die("Failed setting filehandle flags: $!\n");
        };
        if ($@) {
            Carp::carp("Failure setting non-blocking mode on random device '$device': $@");
        }
    }

    # Read data
    my $data;
    my $cnt = read($FH, $data, $bytes);
    close($FH);

    if (defined($cnt)) {
        # Complain if we didn't get all the data we asked for
        if ($cnt < $bytes) {
            Carp::carp("Random device '$device' exhausted");
        }
        # Add data to seed array
        if ($cnt = int($cnt / $INT_SIZE)) {
            push(@{$seed_for{$$prng}}, unpack("$UNPACK_CODE$cnt", $data));
        }
    } else {
        Carp::carp("Failure reading from random device '$device': $!");
    }
};


# Acquire seed data from random.org
my $_src_random_org = sub {
    my $prng  = $_[0];
    my $need  = $_[1];
    my $bytes = $need * $INT_SIZE;

    # Load LWP::UserAgent module
    eval {
        require LWP::UserAgent;
    };
    if ($@) {
        Carp::carp("Failure loading LWP::UserAgent: $@");
        return;
    }

    my $res;
    eval {
        # Create user agent
        my $ua = LWP::UserAgent->new( timeout => 5, env_proxy => 1 );
        # Create request to random.org
        my $req = HTTP::Request->new(GET =>
                "http://www.random.org/cgi-bin/randbyte?nbytes=$bytes");
        # Get the seed
        $res = $ua->request($req);
    };
    if ($@) {
        Carp::carp("Failure contacting random.org: $@");
    } elsif ($res->is_success) {
        # Add data to seed array
        push(@{$seed_for{$$prng}}, unpack("$UNPACK_CODE*", $res->content));
    } else {
        Carp::carp('Failure getting data from random.org: ' . $res->status_line);
    }
};


# Acquire seed data from HotBits
my $_src_hotbits = sub {
    my $prng  = $_[0];
    my $need  = $_[1];
    my $bytes = $need * $INT_SIZE;

    # Load LWP::UserAgent module
    eval {
        require LWP::UserAgent;
    };
    if ($@) {
        Carp::carp("Failure loading LWP::UserAgent: $@");
        return;
    }

    my $res;
    eval {
        # Create user agent
        my $ua = LWP::UserAgent->new( timeout => 5, env_proxy => 1 );
        # HotBits only allows 2048 bytes max.
        if ($bytes > 2048) {
            $bytes = 2048;
            $need  = $bytes / $INT_SIZE;
        }
        # Create request for HotBits
        my $req = HTTP::Request->new(GET =>
                "http://www.fourmilab.ch/cgi-bin/uncgi/Hotbits?fmt=bin&nbytes=$bytes");
        # Get the seed
        $res = $ua->request($req);
    };
    if ($@) {
        Carp::carp("Failure contacting HotBits: $@");
    } elsif ($res->is_success) {
        if ($res->content =~ /exceeded your 24-hour quota/) {
            # Complain about exceeding Hotbits quota
            Carp::carp($res->content);
        } else {
            # Add data to seed array
            push(@{$seed_for{$$prng}}, unpack("$UNPACK_CODE*", $res->content));
        }
    } else {
        Carp::carp('Failure getting data from HotBits: ' . $res->status_line);
    }
};


# Acquire seed data from Win XP random source
my $_src_win32 = sub {
    my $prng  = $_[0];
    my $need  = $_[1];
    my $bytes = $need * $INT_SIZE;

    # Check OS type and version
    if ($^O ne 'MSWin32') {
        Carp::carp("Can't use 'win32' source: Not Win XP");
        return;
    }
    my ($id, $major, $minor) = (Win32::GetOSVersion())[4,1,2];
    if (! defined($minor)) {
        Carp::carp("Can't use 'win32' source: Unable to determine Windows version");
        return;
    }
    if (($id < 2) ||
        ($id == 2 && $major < 5) ||
        ($id == 2 && $major == 5 && $minor < 1))
    {
        Carp::carp("Can't use 'win32' source: Not Win XP [ID: $id, MAJ: $major, MIN: $minor]");
        return;
    }

    eval {
        # Suppress (harmless) warning about Win32::API::Type's INIT block
        local $SIG{__WARN__} = sub {
            if ($_[0] !~ /^Too late to run INIT block/) {
                Carp::carp($_[0]);    # Output other warnings
            }
        };

        # Load Win32::API module
        require Win32::API;

        # Import the random source function
        my $func = Win32::API->new('ADVAPI32.DLL', 'SystemFunction036', 'PN', 'I');
        if (! defined($func)) {
            die("Failure importing 'SystemFunction036': $!\n");
        }

        # Acquire the random data
        my $buffer = chr(0) x $bytes;
        if (! $func->Call($buffer, $bytes)) {
            die("'SystemFunction036' failed: $^E\n");
        }

        # Add data to seed array
        push(@{$seed_for{$$prng}}, unpack("$UNPACK_CODE*", $buffer));
    };
    if ($@) {
        Carp::carp("Failure acquiring Win XP random data: $@");
    }
};


# Seed source subroutine dispatch table
my %_DISPATCH = (
    'random_org' => $_src_random_org,
    'hotbits'    => $_src_hotbits,
    'win32'      => $_src_win32
);


# Acquire seed data from specific sources
$acq_seed = sub {
    my $prng    = $_[0];

    my $sources = $sources_for{$$prng};
    my $seed    = $seed_for{$$prng};

    # Acquire seed data until we have a full seed,
    # or until we run out of sources
    @{$seed} = ();
    for (my $ii=0;
         (@{$seed} < $FULL_SEED) && ($ii < @{$sources});
         $ii++)
    {
        my $src = $sources->[$ii];

        # Determine amount of data needed
        my $need = $FULL_SEED - @{$seed};
        if (($ii+1 < @{$sources}) && looks_like_number($sources->[$ii+1])) {
            if ($sources->[++$ii] < $need) {
                $need = $sources->[$ii];
            }
        }

        if (ref($src) eq 'CODE') {
            # User-supplied seeding subroutine
            &$src($seed, $need);

        } elsif (defined($_DISPATCH{lc($src)})) {
            # Module defined seeding source
            # Execute subroutine ref from dispatch table
            $_DISPATCH{lc($src)}->($prng, $need);

        } elsif (-e $src) {
            # Random device or file
            &$_src_device($src, $prng, $need);

        } else {
            Carp::croak("Unknown seeding source: $src");
        }
    }

    if (! @{$seed}) {
        # Die if no sources
        if (! @{$sources}) {
            Carp::croak('No seed sources specified');
        }

        # Complain about not getting any seed data,
        # and provide a minimal seed
        Carp::carp('No seed data obtained from sources - Setting minimal seed using PID and time');
        push(@{$seed}, $$, time());

    } elsif (@{$seed} < $FULL_SEED) {
        # Complain about not getting a full seed
        Carp::carp('Partial seed - only ' . scalar(@{$seed}) . ' of ' . $FULL_SEED);
    }
};

} # End of lexical scope for package

1;

__END__

=head1 NAME

Math::Random::MT::Auto - Auto-seeded Mersenne Twister PRNGs

=head1 VERSION

This documentation refers to Math::Random::MT::Auto version 4.10.00.

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Math::Random::MT::Auto qw(rand irand shuffle gaussian),
                               '/dev/urandom' => 256,
                               'random_org';

    # Functional interface
    my $die_roll = 1 + int(rand(6));

    my $coin_flip = (irand() & 1) ? 'heads' : 'tails';

    my $deck = shuffle(1 .. 52);

    my $rand_IQ = gaussian(15, 100);

    # OO interface
    my $prng = Math::Random::MT::Auto->new('SOURCE' => '/dev/random');

    my $angle = $prng->rand(360);

    my $decay_interval = $prng->exponential(12.4);

=head1 DESCRIPTION

The Mersenne Twister is a fast pseudorandom number generator (PRNG) that
is capable of providing large volumes (> 10^6004) of "high quality"
pseudorandom data to applications that may exhaust available "truly"
random data sources or system-provided PRNGs such as
L<rand|perlfunc/"rand">.

This module provides PRNGs that are based on the Mersenne Twister.  There
is a functional interface to a single, standalone PRNG, and an OO interface
(based on the inside-out object model) for generating multiple PRNG objects.
The PRNGs are self-seeding, automatically acquiring a (19968-bit) random seed
from user-selectable sources.

=over

=item Random Number Deviates

In addition to integer and floating-point uniformly-distributed random number
deviates (i.e., L<"irand"> and L<"rand">) , this module implements the
following non-uniform deviates as found in I<Numerical Recipes in C>:

=over

=over

=item * Gaussian (normal)

=item * Exponential

=item * Erlang (gamma of integer order)

=item * Poisson

=item * Binomial

=back

=back

=item Shuffling

This module also provides a subroutine/method for shuffling data based on the
Fisher-Yates shuffling algorithm.

=item Support for 64-bit Integers

If Perl has been compiled to support 64-bit integers (do
L<perl -V|perlrun/"-V"> and look for C<use64bitint=define>), then this module
will use a 64-bit-integer version of the Mersenne Twister, thus providing
64-bit random integers and 52-bit random doubles.  The size of integers
returned by L</"irand">, and used by L</"get_seed"> and L</"set_seed"> will be
sized accordingly.

Programmatically, the size of Perl's integers can be determined using the
C<Config> module:

    use Config;
    print("Integers are $Config{'uvsize'} bytes in length\n");

=back

The code for this module has been optimized for speed.  Under Cygwin, it's
2.5 times faster than Math::Random::MT, and under Solaris, it's more than
four times faster.  (Math::Random::MT fails to build under Windows.)

=head1 QUICKSTART

To use this module as a drop-in replacement for Perl's built-in
L<rand|perlfunc/"rand"> function, just add the following to the top of your
application code:

    use strict;
    use warnings;
    use Math::Random::MT::Auto 'rand';

and then just use L</"rand"> as you would normally.  You don't even need to
bother seeding the PRNG (i.e., you don't need to call L</"srand">), as that
gets done automatically when the module is loaded by Perl.

If you need multiple PRNGs, then use the OO interface:

    use strict;
    use warnings;
    use Math::Random::MT::Auto;

    my $prng1 = Math::Random::MT::Auto->new();
    my $prng2 = Math::Random::MT::Auto->new();

    my $rand_num = $prng1->rand();
    my $rand_int = $prng2->irand();

B<CAUTION>: If you want to L<require|perlfunc/"require"> this module, see the
L</"Delayed Importation"> section for important information.

=head1 MODULE DECLARATION

=head2 Subroutine Declarations

By default, this module does not automatically export any of its subroutines.
If you want to use the standalone PRNG, then you should specify the
subroutines you want to use when you declare the module:

    use Math::Random::MT::Auto qw(rand irand shuffle gaussian
                                  exponential erlang poisson binomial
                                  srand get_seed set_seed get_state set_state);

Without the above declarations, it is still possible to use the standalone
PRNG by accessing the subroutines using their fully-qualified names.  For
example:

    my $rand = Math::Random::MT::Auto::rand();

=head2 Module Options

=over

=item Seeding Sources

Starting the PRNGs with a 19968-bit random seed (312 64-bit integers or 624
32-bit integers) takes advantage of their full range of possible internal
vectors states.  This module attempts to acquire such seeds using several
user-selectable sources.

(I would be interested to hear about other random data sources for possible
inclusion in future versions of this module.)

=over

=item Random Devices

Most OSs offer some sort of device for acquiring random numbers.  The
most common are F</dev/urandom> and F</dev/random>.  You can specify the
use of these devices for acquiring the seed for the PRNG when you declare
this module:

    use Math::Random::MT::Auto '/dev/urandom';
      # or
    my $prng = Math::Random::MT::Auto->new('SOURCE' => '/dev/random');

or they can be specified when using L</"srand">.

    srand('/dev/random');
      # or
    $prng->srand('/dev/urandom');

The devices are accessed in I<non-blocking> mode so that if there is
insufficient data when they are read, the application will not hang waiting
for more.

=item File of Binary Data

Since the above devices are just files as far as Perl is concerned, you can
also use random data previously stored in files (in binary format).

    srand('C:\\Temp\\RANDOM.DAT');
      # or
    $prng->srand('/tmp/random.dat');

=item Internet Sites

This module provides support for acquiring seed data from two Internet
sites:  random.org and HotBits.  An Internet connection and
L<LWP::UserAgent> are required to utilize these sources.

    use Math::Random::MT::Auto 'random_org';
      # or
    use Math::Random::MT::Auto 'hotbits';

If you connect to the Internet through an HTTP proxy, then you must set
the L<http_proxy|LWP/"http_proxy"> variable in your environment when using
these sources.  (See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site will only provide a maximum of 2048 bytes of data per
request.  If you want to get the full seed from HotBits, then specify
the C<hotbits> source twice in the module declaration.

    my $prng = Math::Random::MT::Auto->new('SOURCE' => ['hotbits',
                                                        'hotbits']);

=item Windows XP Random Data

Under Windows XP, you can acquire random seed data from the system.

    use Math::Random::MT::Auto 'win32';

To utilize this option, you must have the L<Win32::API> module
installed.

=item User-defined Seeding Source

A subroutine reference may be specified as a seeding source.  When called, it
will be passed three arguments:  A array reference where seed data is to be
added, and the number of integers (64- or 32-bit as the case may be) needed.

    sub MySeeder
    {
        my $seed = $_[0];
        my $need = $_[1];

        while ($need--) {
            my $data = ...;      # Get seed data from your source
            ...
            push(@{$seed}, $data);
        }
    }

    my $prng = Math::Random::MT::Auto->new(\&MySeeder);

=back

The default list of seeding sources is determined when the module is loaded
(actually when the C<import> function is called).  Under Windows XP,
C<win32> is added to the list.  Otherwise, F</dev/urandom> and then
F</dev/random> are checked.  The first one found is added to the list.
Finally, C<random_org> is added.

For the functional interface to the standalone PRNG, these defaults can be
overridden by specifying the desired sources when the module is declared, or
through the use of the L</"srand"> subroutine.  Similarly for the OO
interface, they can be overridden in the
L<-E<gt>new()|/"Math::Random::MT::Auto-E<gt>new"> method when the PRNG is
created, or later using the L</"srand"> method.

Optionally, the maximum number of integers (64- or 32-bits as the case may
be) to be acquired from a particular source may be specified:

    # Get at most 1024 bytes from random.org
    # Finish the seed using data from /dev/urandom
    use Math::Random::MT::Auto 'random_org' => (1024 / $Config{'uvsize'}),
                               '/dev/urandom';

=item Delayed Seeding

Normally, the standalone PRNG is automatically seeded when the module is
loaded.  This behavior can be modified by supplying the C<:!auto> (or
C<:noauto>) flag when the module is declared.  (The PRNG will still be
seeded using data such as L<time()|perlfunc/"time"> and PID
(L<$$|perlvar/"$$">), just in case.)  When the C<:!auto> option is used, the
L</"srand"> subroutine should be imported, and then run before calling any of
the random number deviates.

    use Math::Random::MT::Auto qw(rand srand :!auto);
      ...
    srand();
      ...
    my $rn = rand(10);

=back

=head2 Delayed Importation

If you want to delay the importation of this module using
L<require|perlfunc/"require">, then you need to execute its C<import> function
to complete the module's initialization:

    eval {
        require Math::Random::MT::Auto;
        # Add options to the import call, as desired.
        import Math::Random::MT::Auto qw(rand random_org);
    };

=head1 OBJECT CREATION

The OO interface for this module allows you to create multiple, independent
PRNGs.

If your application will only be using the OO interface, then declare this
module using the L<:!auto|/"Delayed Seeding"> flag to forestall the automatic
seeding of the standalone PRNG:

    use Math::Random::MT::Auto ':!auto';

=over

=item Math::Random::MT::Auto->new

    my $prng = Math::Random::MT::Auto->new( %options );

Creates a new PRNG.  With no options, the PRNG is seeded using the default
sources that were determined when the module was loaded, or that were last
supplied to the L</"srand"> subroutine.

=over

=item 'STATE' => $prng_state

Sets the newly created PRNG to the specified state.  The PRNG will then
function as a clone of the RPNG that the state was obtained from (at the
point when then state was obtained).

When the C<STATE> option is used, any other options are just stored (i.e.,
they are not acted upon).

=item 'SEED' => $seed_array_ref

When the C<STATE> option is not used, this option seeds the newly created
PRNG using the supplied seed data.  Otherwise, the seed data is just
copied to the new object.

=item 'SOURCE' => 'source'

=item 'SOURCE' => ['source', ...]

Specifies the seeding source(s) for the PRNG.  If the C<STATE> and C<SEED>
options are not used, then seed data will be immediately fetched using the
specified sources, and used to seed the PRNG.

The source list is retained for later use by the L</"srand"> method.  The
source list may be replaced by calling the L</"srand"> method.

'SOURCES', 'SRC' and 'SRCS' can all be used as synonyms for 'SOURCE'.

=back

The options above are also supported using lowercase and mixed-case names
(e.g., 'Seed', 'src', etc.).

=item $obj->new

    my $prng2 = $prng1->new( %options );

Creates a new PRNG in the same manner as L</"Math::Random::MT::Auto-E<gt>new">.

=item $obj->clone

    my $prng2 = $prng1->clone();

Creates a new PRNG that is a copy of the referenced PRNG.

=back

=head1 SUBROUTINES/METHODS

When any of the I<functions> listed below are invoked as subroutines, they
operates with respect to the standalone PRNG.  For example:

    my $rand = rand();

When invoked as methods, they operate on the referenced PRNG object:

    my $rand = $prng->rand();

For brevity, only usage examples for the functional interface are given below.

=over

=item rand

    my $rn = rand();
    my $rn = rand($num);

Behaves exactly like Perl's built-in L<rand|perlfunc/"rand">, returning a
number uniformly distributed in [0, $num).  ($num defaults to 1.)

NOTE: If you still need to access Perl's built-in L<rand|perlfunc/"rand">
function, you can do so using C<CORE::rand()>.

=item irand

    my $int = irand();

Returns a random integer.  For 32-bit integer Perl, the range is 0 to
2^32-1 (0xFFFFFFFF) inclusive.  For 64-bit integer Perl, it's 0 to 2^64-1
inclusive.

This is the fastest way to obtain random numbers using this module.

=item shuffle

    my $shuffled = shuffle($data, ...);
    my $shuffled = shuffle(@data);
    my $shuffled = shuffle(\@data);

Returns an array reference containing a random ordering of the supplied
arguments (i.e., shuffled) by using the Fisher-Yates shuffling algorithm.  If
called with a single array reference (fastest method), the contents of the
array are shuffled in situ.

=item gaussian

    my $gn = gaussian();
    my $gn = gaussian($sd);
    my $gn = gaussian($sd, $mean);

Returns floating-point random numbers from a Gaussian (normal) distribution
(i.e., numbers that fit a bell curve).  If called with no arguments, the
distribution uses a standard deviation of 1, and a mean of 0.  Otherwise,
the supplied argument(s) will be used for the standard deviation, and the
mean.

=item exponential

    my $xn = exponential();
    my $xn = exponential($mean);

Returns floating-point random numbers from an exponential distribution.  If
called with no arguments, the distribution uses a mean of 1.  Otherwise, the
supplied argument will be used for the mean.

An example of an exponential distribution is the time interval between
independent Poisson-random events such as radioactive decay.  In this case,
the mean is the average time between events.  This is called the I<mean life>
for radioactive decay, and its inverse is the decay constant (which represents
the expected number of events per unit time).  The well known term
I<half-life> is given by C<mean * ln(2)>.

=item erlang

    my $en = erlang($order);
    my $en = erlang($order, $mean);

Returns floating-point random numbers from an Erlang distribution of specified
order.  The order must be a positive integer (> 0).  The mean, if not
specified, defaults to 1.

The Erlang distribution is the distribution of the sum of C<$order>
independent identically distributed random variables each having an
exponential distribution.  (It is a special case of the gamma distribution for
which C<$order> is a positive integer.)  When C<$order = 1>, it is just the
exponential distribution.  It is named after A. K. Erlang who developed it to
predict waiting times in queuing systems.

=item poisson

    my $pn = poisson($mean);
    my $pn = poisson($rate, $time);

Returns integer random numbers (>= 0) from a Poisson distribution of specified
mean (rate * time = mean).  The mean must be a positive value (> 0).

The Poisson distribution predicts the probability of the number of
Poisson-random events occurring in a fixed time if these events occur with a
known average rate.  Examples of events that can be modeled as Poisson
distributions include:

=over

=over

=item * The number of decays from a radioactive sample within a given time
period.

=item * The number of cars that pass a certain point on a road within a given
time period.

=item * The number of phone calls to a call center per minute.

=item * The number of road kill found per a given length of road.

=back

=back

=item binomial

    my $bn = binomial($prob, $trials);

Returns integer random numbers (>= 0) from a binomial distribution.  The
probability (C<$prob>) must be between 0.0 and 1.0 (inclusive), and the number
of trials must be >= 0.

The binomial distribution is the discrete probability distribution of the
number of successes in a sequence of C<$trials> independent Bernoulli trials
(i.e., yes/no experiments), each of which yields success with probability
C<$prob>.

If the number of trials is very large, the binomial distribution may be
approximated by a Gaussian distribution. If the average number of successes
is small (C<$prob * $trials < 1>), then the binomial distribution can be
approximated by a Poisson distribution.

=item srand

    srand();
    srand('source', ...);

This (re)seeds the PRNG.  It may be called anytime reseeding of the PRNG is
desired (although this should normally not be needed).

When the L<:!auto|/"Delayed Seeding"> flag is used, the C<srand> subroutine
should be called before any other access to the standalone PRNG.

When called without arguments, the previously determined/specified seeding
source(s) will be used to seed the PRNG.

Optionally, seeding sources may be supplied as arguments as when using the
L<'SOURCE'|/"Seeding Sources"> option.  (These sources will be saved and used
again if C<srand> is subsequently called without arguments).

    # Get 250 integers of seed data from Hotbits,
    #  and then get the rest from /dev/random
    srand('hotbits' => 250, '/dev/random');

If called with integer data (a list of one or more value, or an array of
values), or a reference to an array of integers, these data will be passed to
L</"set_seed"> for use in reseeding the PRNG.

NOTE: If you still need to access Perl's built-in L<srand|perlfunc/"srand">
function, you can do so using C<CORE::srand($seed)>.

=item get_seed

    my $seed = get_seed();

Returns an array reference containing the seed last sent to the PRNG.

NOTE: Changing the data in the referenced array will not cause any changes in
the PRNG (i.e., it will not reseed it).  You need to use L</"srand"> or
L</"set_seed"> for that.

=item set_seed

    set_seed($seed, ...);
    set_seed(@seed);
    set_seed(\@seed);

When called with integer data (a list of one or more value, or an array of
values), or a reference to an array of integers, these data will be used to
reseed the PRNG.

Together with L</"get_seed">, C<set_seed> may be useful for setting up
identical sequences of random numbers based on the same seed.

It is possible to seed the PRNG with more than 19968 bits of data (312 64-bit
integers or 624 32-bit integers).  However, doing so does not make the PRNG
"more random" as 19968 bits more than covers all the possible PRNG state
vectors.

=item get_state

    my $state = get_state();

Returns an array reference containing the current state vector of the PRNG.

Note that the state vector is not a full serialization of the PRNG, which
would also require information on the sources and seed.

=item set_state

    set_state($state);

Sets a PRNG to the state contained in an array reference previously obtained
using L</"get_state">.

    # Get the current state of the PRNG
    my $state = get_state();

    # Run the PRNG some more
    my $rand1 = irand();

    # Restore the previous state of the PRNG
    set_state($state);

    # Get another random number
    my $rand2 = irand();

    # $rand1 and $rand2 will be equal.

B<CAUTION>:  It should go without saying that you should not modify the
values in the state vector obtained from L</"get_state">.  Doing so and then
feeding it to L</"set_state"> would be (to say the least) naughty.

In conjunction with L<Data::Dumper> and L<do(file)|perlfunc/"do">,
L</"get_state"> and L</"set_state"> can be used to save and then reload the
state vector between application runs.  (See L</"EXAMPLES"> below.)

=back

=head1 THREAD SUPPORT

This module is thread-safe for PRNGs created through the OO interface for
Perl v5.7.2 and beyond.

For Perl prior to v5.7.2, the PRNG objects created in the parent will be
I<broken> in the thread once it is created.  Therefore, new PRNG objects must
be created in the thread.

The standalone PRNG is not thread-safe, and hence should not be used in
threaded applications.

Because of the complexities of its object's attributes, this module does not
support sharing objects between threads via L<threads::shared>.

=head1 IMPLEMENTING SUBCLASSES

This package uses the I<inside-out> object model (see informational links
under L</"SEE ALSO">).  This object model offers a number of advantages, and
the use of L<attributes> by this class eliminates the need to implement
C<CLONE> and C<DESTROY> subroutines in subclasses.

Further, the objects created are not the usual blessed hash references: In the
case of this package, they are blessed, readonly scalar references that
contain a unique ID for the object.  This ID is used to track object
attributes both in this class and in subclasses.

The subclass L<Math::Random::MT::Auto::Range> included with this module's
distribution is provided as an example of how to implement subclasses of this
package.  Execute the following to find the location of its source code file:

    perldoc -l Math::Random::MT::Auto::Range

=head1 EXAMPLES

=over

=item Cloning the standalone PRNG to an object

    use Math::Random::MT::Auto qw(rand irand get_state);

    my $prng = Math::Random::MT::Auto->new('STATE' => get_state());

The standalone PRNG and the PRNG object will now return the same sequence
of pseudorandom numbers.

=item Save state to file

    use Data::Dumper;
    use Math::Random::MT::Auto qw(rand irand get_state);

    my $state = get_state();
    if (open(my $FH, '>', '/tmp/rand_state_data.tmp')) {
        print($FH Data::Dumper->Dump([$state], ['state']));
        print($FH "1;\n");
        close($FH);
    }

=item Use state as stored above

    use Math::Random::MT::Auto qw(rand irand set_state);

    our $state;
    my $rc = do('/tmp/rand_state_data.tmp');
    unlink('/tmp/rand_state_data.tmp');
    if ($rc) {
        set_state($state);
    }

=back

Included in this module's distribution are several sample programs (located
in the F<samples> sub-directory) that illustrate the use of the various
random number deviates and other features supported by this module.

=head1 DIAGNOSTICS

=head2 WARNINGS

Warnings are generated by this module primarily when problems are encountered
while trying to obtain random seed data for the PRNGs.  This may occur after
the module is loaded, after a PRNG object is created, or after calling
L</"srand">.

These seed warnings are not critical in nature.  The PRNG will still be seeded
(at a minimum using data such as L<time()|perlfunc/"time"> and PID
(L<$$|perlvar/"$$">)), and can be used safely.

The following illustrates how such warnings can be trapped for programmatic
handling:

    my @WARNINGS;
    BEGIN {
        $SIG{__WARN__} = sub { push(@WARNINGS, @_); };
    }

    use Math::Random::MT::Auto;

    # Check for standalone PRNG warnings
    if (@WARNINGS) {
        # Handle warnings as desired
        ...
        # Clear warnings
        undef(@WARNINGS);
    }

    my $prng = Math::Random::MT::Auto->new();

    # Check for PRNG object warnings
    if (@WARNINGS) {
        # Handle warnings as desired
        ...
        # Clear warnings
        undef(@WARNINGS);
    }

=over

=item * Failure opening random device '...': ...

The specified device (e.g., /dev/random) could not be opened by the module.
Further diagnostic information should be included with this warning message
(e.g., device does not exist, permission problem, etc.).

=item * Failure setting non-blocking mode on random device '...': ...

The specified device could not be set to I<non-blocking> mode.  Further
diagnostic information should be included with this warning message
(e.g., permission problem, etc.).

=item * Failure reading from random device '...': ...

A problem occurred while trying to read from the specified device.  Further
diagnostic information should be included with this warning message.

=item * Random device '...' exhausted

The specified device did not supply the requested number of random numbers for
the seed.  It could possibly occur if F</dev/random> is used too frequently.
It will occur if the specified device is a file, and it does not have enough
data in it.

=item * Failure loading LWP::UserAgent: ...

To utilize the option of acquiring seed data from Internet sources, you need
to install the L<LWP::UserAgent> module.

=item * Failure contacting random.org: ...

=item * Failure contacting HotBits: ...

=item * Failure getting data from random.org: 500 Can't connect to www.random.org:80 (connect: timeout)

=item * Failure getting data from HotBits: 500 Can't connect to www.fourmilab.ch:80 (connect: timeout)

You need to have an Internet connection to utilize
L<random.org or HotBits|/"Internet Sites"> as random seed sources.

If you connect to the Internet through an HTTP proxy, then you must set the
L<http_proxy|LWP/"http_proxy"> variable in your environment when using the
Internet seed sources.  (See L<LWP::UserAgent/"Proxy attributes">.)

This module sets a 5 second timeout for Internet connections so that if
something goes awry when trying to get seed data from an Internet source,
your application will not hang for an inordinate amount of time.

=item * You have exceeded your 24-hour quota for HotBits.

The L<HotBits|/"Internet Sites"> site has a quota on the amount of data you
can request in a 24-hour period.  (I don't know how big the quota is.)
Therefore, this source may fail to provide any data if used too often.

=item * Can't use 'win32' source: Not Win XP

=item * Can't use 'win32' source: Unable to determine Windows version

=item * Can't use 'win32' source: Not Win XP ...

The L<win32|/"Windows XP Random Data"> random data source is only available
under Windows XP (and later).

=item * Failure acquiring Win XP random data: ...

A problem occurred while trying to acquire seed data from the Window XP random
source.  Further diagnostic information should be included with this warning
message.

=item * No seed data obtained from sources - Setting minimal seed using PID and time

This message will occur in combination with some other message(s) above.

If the module cannot acquire any seed data from the specified sources, then
data such as L<time()|perlfunc/"time"> and PID (L<$$|perlvar/"$$">) will be
used to seed the PRNG.

=item * Partial seed - only X of Y

This message will occur in combination with some other message(s) above.  It
informs you of how much seed data was needed and acquired.

=back

=head2 ERRORS

These errors indicate that there is something I<fubar> in your code.

=over

=item * Missing argument to 'set_seed'

L</"set_seed"> must be called with an array ref, or a list of integer seed
data.

=item * 'set_state' requires an array ref

L</"set_state"> must be called with an array reference previously obtained
using L</"get_state">.

=item * Invalid argument to Math::Random::MT::Auto->new(): Value for 'STATE' is not an array ref

The L<'STATE'|/"'STATE' =E<gt> $prng_state"> argument must be an array
reference previously obtained using L</"get_state">.

=item * No seed sources specified - Setting minimal seed using PID and time

This message occurs when you L<require|perlfunc/"require"> this module, but
fail to execute its C<import> function.  See L</"Delayed Importation"> for
details.

=item * Invalid argument to Math::Random::MT::Auto->new(): ...

Something is messed up with your argument list to
L<-E<gt>new()|/"Math::Random::MT::Auto-E<gt>new">.

=item * Unknown seeding source: ...

The specified seeding source is not recognized by this module.  See
L</"Seeding Sources"> for more information.

=back

=head1 PERFORMANCE

Under Cygwin, this module is 2.5 times faster than Math::Random::MT, and under
Solaris, it's more than four times faster.  (Math::Random::MT fails to build
under Windows.)  The file F<samples/timings.pl>, included in this module's
distribution, can be used to compare timing results.

If you connect to the Internet via a phone modem, acquiring seed data may take
a second or so.  This delay might be apparent when your application is first
started, or after creating a new PRNG object.  This is especially true if you
specify the L<hotbits|/"Internet Sites"> source twice (so as to get the full
seed from the HotBits site) as this results in two accesses to the Internet.
(If F</dev/urandom> is available on your machine, then you should definitely
consider using the Internet sources only as a secondary source.)

=head1 DEPENDENCIES

=head2 Installation

A 'C' compiler is required for building this module.

This module uses the following 'standard' modules for installation:

=over

=over

=item ExtUtils::MakeMaker

=item File::Spec

=item Test::More

=back

=back

=head2 Operation

Requires Perl 5.6.0 or later.

This module uses the following 'standard' modules:

=over

=over

=item attributes

=item Carp

=item Scalar::Util - Standard in 5.8; install from CPAN otherwise

=item Dynaloader

=back

=back

To utilize the option of acquiring seed data from Internet sources, you need
to install the L<LWP::UserAgent> module.

Under Windows XP, to utilize the option of acquiring seed data from the
system's random data source, you need to install the L<Win32::API> module.

=head1 BUGS AND LIMITATIONS

There are no known bugs in this module.

This module does not support multiple inheritance.

Please submit any bugs, problems, suggestions, patches, etc. to:
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Math-Random-MT-Auto>

=head1 SEE ALSO

The Mersenne Twister is the (current) quintessential pseudorandom number
generator. It is fast, and has a period of 2^19937 - 1.  The Mersenne
Twister algorithm was developed by Makoto Matsumoto and Takuji Nishimura.
It is available in 32- and 64-bit integer versions.
L<http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>

Wikipedia entries on the Mersenne Twister and pseudorandom number generators,
in general:
L<http://en.wikipedia.org/wiki/Mersenne_twister>, and
L<http://en.wikipedia.org/wiki/Pseudorandom_number_generator>

random.org generates random numbers from radio frequency noise.
L<http://random.org/>

HotBits generates random number from a radioactive decay source.
L<http://www.fourmilab.ch/hotbits/>

OpenBSD random devices:
L<http://www.openbsd.org/cgi-bin/man.cgi?query=arandom&sektion=4&apropos=0&manpath=OpenBSD+Current&arch=>

FreeBSD random devices:
L<http://www.freebsd.org/cgi/man.cgi?query=random&sektion=4&apropos=0&manpath=FreeBSD+5.3-RELEASE+and+Ports>

Man pages for F</dev/random> and F</dev/urandom> on Unix/Linux/Cygwin/Solaris:
L<http://www.die.net/doc/linux/man/man4/random.4.html>

Windows XP random data source:
L<http://blogs.msdn.com/michael_howard/archive/2005/01/14/353379.aspx>

Fisher-Yates Shuffling Algorithm:
L<http://en.wikipedia.org/wiki/Shuffling_playing_cards#Shuffling_algorithms>,
and L<shuffle() in List::Util|List::Util>

Non-uniform random number deviates in I<Numerical Recipes in C>,
Chapters 7.2 and 7.3:
L<http://www.library.cornell.edu/nr/bookcpdf.html>

Inside-out Object Model:
L<http://www.perlmonks.org/index.pl?node_id=219378>,
L<http://www.perlmonks.org/index.pl?node_id=483162>,
L<http://www.perlmonks.org/index.pl?node_id=221145>, and
Chapter 15 of I<Perl Best Practices> by Damian Conway

L<Math::Random::MT::Auto::Range> - Subclass of Math::Random::MT::Auto that
creates range-valued PRNGs

L<attributes>

L<LWP::UserAgent>

L<Math::Random::MT>

L<Net::Random>

=head1 AUTHOR

Jerry D. Hedden, S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

=head1 COPYRIGHT AND LICENSE

A C-Program for MT19937 (32- and 64-bit versions), with initialization
improved 2002/1/26.  Coded by Takuji Nishimura and Makoto Matsumoto,
and including Shawn Cokus's optimizations.

 Copyright (C) 1997 - 2004, Makoto Matsumoto and Takuji Nishimura,
  All rights reserved.
 Copyright (C) 2005, Mutsuo Saito, All rights reserved.
 Copyright 2005 Jerry D. Hedden <jdhedden AT 1979 DOT usna DOT com>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

3. The names of its contributors may not be used to endorse or promote
   products derived from this software without specific prior written
   permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER
OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 Any feedback is very welcome.
 m-mat AT math DOT sci DOT hiroshima-u DOT ac DOT jp
 http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html

=cut
