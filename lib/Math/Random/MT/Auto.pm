package Math::Random::MT::Auto; {

use strict;
use warnings;

use 5.006;
use Scalar::Util 1.16 qw(blessed looks_like_number weaken);
use Carp ();

use base 'DynaLoader';

our $VERSION = '4.04.00';

bootstrap Math::Random::MT::Auto $VERSION;

### Package Global Variables ###

# Object attribute hashes used by inside-out object model
#
# Data stored in these hashes is keyed to the object by a unique ID.  Because
# this class creates the objects, it can use the address of the internal PRNG
# memory for the object's ID.  Note, however, that subclasses cannot use this
# same key scheme because this class can change that ID (and does so when
# cloning objects for threads).

my %SOURCE;     # Random seed sources
my %SEED;       # Last seed sent to PRNG
my %WARN;       # Seeding error messages

# Maintains weak references to PRNG objects for thread cloning
my %REGISTRY;

### Standalone PRNG data
# Standalone PRNG pseudo-object - Ref to pointer to internal PRNG memory
my $SA = do { \(my $prng = Math::Random::MT::Auto::_internal::get_sa_prng()) };
$SOURCE{$$SA} = [];  # Global default sources - set up in import()
$SEED{$$SA}   = [];
$WARN{$$SA}   = [];


### Module Initialization ###

# Handles importation of random functions,
# specification of seeding sources by the user,
# and auto-seeding of the standalone PRNG.
sub import
{
    my $class = shift;   # Not used

    my $auto_seed = 1;   # Flag for auto-seeding standalone PRNG

    # Exportable functions
    my %SYMS;
    @SYMS{qw(rand irand shuffle gaussian
             exponential erlang poisson binomial
             srand get_warnings get_seed
             set_seed get_state set_state)} = undef;

    # Handle entries in the import list
    while (my $sym = shift) {
        if (exists($SYMS{lc($sym)})) {
            # Export function names
            no strict 'refs';
            *{caller().'::'.$sym} = \&{lc($sym)};

        } elsif ($sym =~ /^:(no|!)?auto$/i) {
            # To auto-seed (:auto is default) or not (:!auto or :noauto)
            $auto_seed = not defined($1);

        } else {
            # User-specified seed acquisition sources
            # or user-defined seed acquisition functions
            push(@{$SOURCE{$$SA}}, $sym);
            # Max. count for source, if any
            if (@_ && looks_like_number($_[0])) {
                push(@{$SOURCE{$$SA}}, shift);
            }
        }
    }

    # Set up default seed sources, if none specified by user
    if (! @{$SOURCE{$$SA}}) {
        if ($^O eq 'MSWin32') {
            my ($id, $major, $minor) = (Win32::GetOSVersion())[4,1,2];
            if (defined($minor) &&
                (($id > 2) ||
                 ($id == 2 && $major > 5) ||
                 ($id == 2 && $major == 5 && $minor >= 1)))
            {
                push(@{$SOURCE{$$SA}}, 'win32');
            }

        } elsif (-e '/dev/urandom') {
            push(@{$SOURCE{$$SA}}, '/dev/urandom');

        } elsif (-e '/dev/random') {
            push(@{$SOURCE{$$SA}}, '/dev/random');
        }
        push(@{$SOURCE{$$SA}}, 'random_org');
    }


    # Auto seed the standalone PRNG.
    if ($auto_seed) {
        # Automatically acquire seed from sources
        Math::Random::MT::Auto::_internal::acq_seed($SOURCE{$$SA},
                                                    $SEED{$$SA},
                                                    $WARN{$$SA});
    } else {
        # Minimal seed when ':!auto' specified
        push(@{$SEED{$$SA}}, $$, time(), $$SA);
    }

    # Seed the PRNG
    Math::Random::MT::Auto::_internal::seed_prng($SA, $SEED{$$SA});
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

            # Get current state from parent PRNG's memory
            #   which is currently shared
            my $state = Math::Random::MT::Auto::_internal::get_state($obj);

            # Create new memory for this cloned PRNG object
            $$obj = Math::Random::MT::Auto::_internal::new_prng();

            # Set state for this cloned PRNG object
            Math::Random::MT::Auto::_internal::set_state($obj, $state);

            # Relocate object data
            $SOURCE{$$obj} = delete($SOURCE{$old_id});
            $SEED{$$obj}   = delete($SEED{$old_id});
            $WARN{$$obj}   = delete($WARN{$old_id});

            # Save weak reference to this cloned object
            weaken($REGISTRY{$$obj} = $obj);
        }
    }
}


### Dual-Interface (Functional and OO) Subroutines ###

# Starts PRNG with random seed using specified sources (if any)
sub srand
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    if (@_) {
        # Check if sent seed by mistake
        if (looks_like_number($_[0]) || ref($_[0]) eq 'ARRAY') {
            if (blessed($obj)) {
                $obj->set_seed(@_);
            } else {
                set_seed(@_);
            }
            return;
        }

        # Save specified sources
        @{$SOURCE{$$obj}} = @_;
    }

    # Acquire seed from sources
    Math::Random::MT::Auto::_internal::acq_seed($SOURCE{$$obj},
                                                $SEED{$$obj},
                                                $WARN{$$obj});
    # Seed the PRNG
    Math::Random::MT::Auto::_internal::seed_prng($obj, $SEED{$$obj});
}


# Returns list of warnings generated while acquiring seed data
sub get_warnings
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    # If arg is true, then send warnings and clear the warnings array
    if ($_[0]) {
        my @warnings = @{$WARN{$$obj}};
        $WARN{$$obj} = [];
        return (@warnings);
    }

    # Just send a copy of the warnings
    return (@{$WARN{$$obj}});
}


# Return ref to PRNG's saved seed (if any)
sub get_seed
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    return ($SEED{$$obj});
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
        @{$SEED{$$obj}} = @{$_[0]};
    } else {
        @{$SEED{$$obj}} = @_;
    }

    # Seed the PRNG
    Math::Random::MT::Auto::_internal::seed_prng($obj, $SEED{$$obj});
}


# Return copy of PRNG's current state
sub get_state
{
    # Generalize for both OO and standalone PRNGs
    my $obj = (blessed($_[0])) ? shift : $SA;

    return (Math::Random::MT::Auto::_internal::get_state($obj));
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

    Math::Random::MT::Auto::_internal::set_state($obj, $state);
}


### OO Methods ###

# Constructor - creates a new PRNG object
sub new
{
    my $thing = shift;
    my $class = ref($thing) || $thing;

    # Create object - Ref to pointer to internal PRNG memory
    my $self = do { \(my $prng = Math::Random::MT::Auto::_internal::new_prng()) };
    bless($self, $class);

    # Default initializations
    $SOURCE{$$self} = [];
    $SEED{$$self}   = [];
    $WARN{$$self}   = [];
    my $state;

    # Save weakened reference to object for thread cloning
    weaken($REGISTRY{$$self} = $self);

    # Handle user-supplied arguments
    my $arg_cnt = @_;
    while (my $arg = shift) {
        if ($arg =~ /^(source|src)s?$/i) {
            # Make sure source is saved as an array ref
            my $src = shift;
            $SOURCE{$$self} = (ref($src) eq 'ARRAY') ? $src : [ $src ];

        } elsif ($arg =~ /^seed$/i) {
            # Make sure seed is saved as an array ref
            my $seed = shift;
            $SEED{$$self} = (ref($seed) eq 'ARRAY') ? $seed : [ $seed ];

        } elsif ($arg =~ /^state$/i) {
            $state = shift;
            if (ref($state) ne 'ARRAY') {
                Carp::croak('Invalid argument to '.__PACKAGE__.'::new(): value for \'STATE\' is not an array ref');
            }

        } else {
            Carp::croak('Invalid argument to '.__PACKAGE__."::new(): $arg");
        }
    }

    # Initialize
    if (ref($thing)) {
        # $thing->new(...) was called
        if ($arg_cnt == 0) {
            # $thing->new() called with no args - 'clone' the PRNG
            @{$SOURCE{$$self}} = @{$SOURCE{$$thing}};
            @{$SEED{$$self}}   = @{$SEED{$$thing}};
            $state = Math::Random::MT::Auto::_internal::get_state($thing);

        } else {
            # Copy object's sources, if none provided
            if (! @{$SOURCE{$$self}}) {
                @{$SOURCE{$$self}} = @{$SOURCE{$$thing}};
            }
        }

    } else {
        # CLASS->new(...) was called
        # Use default sources (from standalone PRNG), if none provided
        if (! @{$SOURCE{$$self}}) {
            @{$SOURCE{$$self}} = @{$SOURCE{$$SA}};
        }
    }

    # If state is specified, then use it
    if ($state) {
        Math::Random::MT::Auto::_internal::set_state($self, $state);

    } else {
        # Acquire seed, if none provided
        if (! @{$SEED{$$self}}) {
            Math::Random::MT::Auto::_internal::acq_seed($SOURCE{$$self},
                                                        $SEED{$$self},
                                                        $WARN{$$self});
        }

        # Seed the PRNG
        Math::Random::MT::Auto::_internal::seed_prng($self, $SEED{$$self});
    }

    return ($self);
}


# Object Destructor
sub DESTROY {
    my $self = $_[0];

    # Delete all data used for the object
    Math::Random::MT::Auto::_internal::free_prng($self);
    delete($SOURCE{$$self});
    delete($SEED{$$self});
    delete($WARN{$$self});

    # Remove object from thread cloning registry
    delete($REGISTRY{$$self});
}

} # End of lexical scope for main package


### Internal Package ###

package Math::Random::MT::Auto::_internal; {

use Config ();
use Scalar::Util 1.16 qw(looks_like_number);


# Size of Perl's integers (32- or 64-bit)
my $INT_SIZE = $Config::Config{'uvsize'};
my $UNPACK_CODE = ($INT_SIZE == 8) ? 'Q' : 'L';


# Seed source subroutine dispatch table
my %dispatch = (
    'random_org' => \&src_random_org,
    'hotbits'    => \&src_hotbits,
    'win32'      => \&src_win32
);


# Acquire seed data from specific sources
sub acq_seed
{
    my $sources  = $_[0];
    my $seed     = $_[1];
    my $warnings = $_[2];

    @$seed = ();
    my $FULL_SEED = 2496 / $INT_SIZE;

    for (my $ii=0; $ii < @$sources; $ii++) {
        my $source = $$sources[$ii];

        # Determine amount of data needed
        my $need = $FULL_SEED - @$seed;
        if (($ii+1 < @$sources) && looks_like_number($$sources[$ii+1])) {
            if ($$sources[++$ii] < $need) {
                $need = $$sources[$ii];
            }
        }

        if (ref($source) eq 'CODE') {
            # User supplied seeding function
            &$source($seed, $need);

        } else {
            if (defined($dispatch{lc($source)})) {
                # Module defined seeding source
                $dispatch{lc($source)}($seed, $need, $warnings);

            } elsif (-e $source) {
                # Random device or file
                src_device($source, $seed, $need, $warnings);

            } else {
                push(@$warnings, "Unknown seeding source: $source");
            }
        }

        # Check if done
        if (@$seed >= $FULL_SEED) {
            last;
        }
    }

    # Check for full seed size
    if (@$seed < $FULL_SEED) {
        if (! @$sources) {
            push(@$warnings, 'No seed sources specified');
        } else {
            push(@$warnings, 'Partial seed - only ' . scalar(@$seed) . ' of ' . $FULL_SEED);
        }
        if (! @$seed) {
            push(@$seed, $$, time());   # Minimal seed
        }
    }
}


# Acquire seed data from a device/file
sub src_device
{
    my $device   = $_[0];
    my $seed     = $_[1];
    my $need     = $_[2];
    my $warnings = $_[3];
    my $bytes    = $need * $INT_SIZE;

    # Try opening device/file
    my $FH;
    if (! open($FH, $device)) {
        push(@$warnings, "Failure opening $device $!");
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
            push(@$warnings, "Failure setting non-blocking mode: $@");
        }
    }

    # Read data
    my $data;
    my $cnt = read($FH, $data, $bytes);
    close($FH);

    # Add data to seed array
    if (defined($cnt)) {
        if ($cnt < $bytes) {
            push(@$warnings, "$device exhausted");
        }
        if ($cnt = int($cnt / $INT_SIZE)) {
            push(@$seed, unpack("$UNPACK_CODE$cnt", $data));
        }
    } else {
        push(@$warnings, "Failure reading from $device: $!");
    }
}


# Acquire seed data from random.org
sub src_random_org
{
    my $seed     = $_[0];
    my $need     = $_[1];
    my $warnings = $_[2];
    my $bytes    = $need * $INT_SIZE;

    # Load LWP::UserAgent module
    eval {
        require LWP::UserAgent;
    };
    if ($@) {
        push(@$warnings, "Failure loading LWP::UserAgent: $@");
        return;
    }

    my $res;
    eval {
        # Create user agent
        my $ua = LWP::UserAgent->new( timeout => 10, env_proxy => 1 );
        # Create request to random.org
        my $req = HTTP::Request->new(GET =>
                "http://www.random.org/cgi-bin/randbyte?nbytes=$bytes");
        # Get the seed
        $res = $ua->request($req);
    };
    if ($@) {
        push(@$warnings, "Failure contacting random.org: $@");
    } elsif ($res->is_success) {
        # Add data to seed array
        push(@$seed, unpack("$UNPACK_CODE*", $res->content));
    } else {
        push(@$warnings, 'Failure getting data from random.org: '
                            . $res->status_line);
    }
}


# Acquire seed data from HotBits
sub src_hotbits
{
    my $seed     = $_[0];
    my $need     = $_[1];
    my $warnings = $_[2];
    my $bytes    = $need * $INT_SIZE;

    # Load LWP::UserAgent module
    eval {
        require LWP::UserAgent;
    };
    if ($@) {
        push(@$warnings, "Failure loading LWP::UserAgent: $@");
        return;
    }

    my $res;
    eval {
        # Create user agent
        my $ua = LWP::UserAgent->new( timeout => 10, env_proxy => 1 );
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
        push(@$warnings, "Failure contacting HotBits: $@");
    } elsif ($res->is_success) {
        if ($res->content =~ /exceeded your 24-hour quota/) {
            push(@$warnings, $res->content);
        } else {
            # Add data to seed array
            push(@$seed, unpack("$UNPACK_CODE*", $res->content));
        }
    } else {
        push(@$warnings, 'Failure getting data from HotBits: '
                            . $res->status_line);
    }
}


# Acquire seed data from Win XP random source
sub src_win32
{
    my $seed     = $_[0];
    my $need     = $_[1];
    my $warnings = $_[2];
    my $bytes    = $need * $INT_SIZE;

    # Check OS type and version
    if ($^O ne 'MSWin32') {
        push(@$warnings, "Can't use 'win32' source: Not Win XP");
        return;
    }
    my ($id, $major, $minor) = (Win32::GetOSVersion())[4,1,2];
    if (! defined($minor)) {
        push(@$warnings, "Can't use 'win32' source: Unable to determine Windows version");
        return;
    }
    if (($id < 2) ||
        ($id == 2 && $major < 5) ||
        ($id == 2 && $major == 5 && $minor < 1))
    {
        push(@$warnings, "Can't use 'win32' source: Not Win XP [ID: $id, MAJ: $major, MIN: $minor]");
        return;
    }

    eval {
        # Suppress warning about Win32::API::Type's INIT block
        local %SIG;
        $SIG{__WARN__} = sub { if ($_[0] !~ /^Too late to run INIT block/) {
                                    warn($_[0]);
                               } };

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
        push(@$seed, unpack("$UNPACK_CODE*", $buffer));
    };
    if ($@) {
        push(@$warnings, "Failure acquiring Win XP random data: $@");
    }
}

} # End of lexical scope for internal package

1;

__END__

=head1 NAME

Math::Random::MT::Auto - Auto-seeded Mersenne Twister PRNGs

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

The Mersenne Twister is a fast pseudo-random number generator (PRNG) that
is capable of providing large volumes (> 10^6004) of "high quality"
pseudo-random data to applications that may exhaust available "truly"
random data sources or system-provided PRNGs such as
L<rand|perlfunc/"rand">.

This module provides PRNGs that are based on the Mersenne Twister.  There
is a functional interface to a single, standalone PRNG, and an OO interface
(based on the inside-out object model) for generating multiple PRNG objects.
The PRNGs are self-seeding, automatically acquiring a (19968-bit) random seed
from user-selectable sources.

In addition to integer and floating-point uniformly-distributed random number
deviates, this module implements the following non-uniform deviates as found
in I<Numerical Recipes in C>:

=over

=item * Gaussian (normal)

=item * Exponential

=item * Erlang (gamma of integer order)

=item * Poisson

=item * Binomial

=back

This module also provides a function/method for shuffling data based on the
Fisher-Yates shuffling algorithm.

This module is thread-safe with respect to its OO interface for Perl v5.7.2
and beyond.  (The standalone PRNG is not thread-safe.)

For Perl compiled to support 64-bit integers, this module will use a 64-bit
version of the Mersenne Twister algorithm, thus providing 64-bit random
integers (and 52-bit random doubles).  (32-bits otherwise.)

The code for this module has been optimized for speed.  Under Windows, it's
more than twice as fast as Math::Random::MT, and under Solaris, it's more than
four times faster.

=head2 Quickstart

To use this module as a drop-in replacement for Perl's
L<rand|perlfunc/"rand"> function, just add the following to the top of your
application code:

  use strict;
  use warnings;
  use Math::Random::MT::Auto qw(rand);

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

=head2 64-bit Support

If Perl has been compiled to support 64-bit integers (do
L<perl -V|perlrun/"-V"> and look for
C<use64bitint=define>), then this module will use a
64-bit-integer version of the Mersenne Twister.  Otherwise, 32-bit integers
will be used.  The size of integers returned by L</"irand">, and used by
L</"get_seed"> and L</"set_seed"> will be sized accordingly.

Programmatically, the size of Perl's integers can be determined using the
C<Config> module:

  use Config;

  print("Integers are $Config{'uvsize'} bytes in length\n");

=head2 Seeding Sources

Starting the PRNGs with a 19968-bit random seed (312 64-bit integers or 624
32-bit integers) takes advantage of their full range of possible internal
vectors states.  This module attempts to acquire such seeds using several
user-selectable sources.

=over

=item Random Devices

Most OSs offer some sort of device for acquiring random numbers.  The
most common are F</dev/urandom> and F</dev/random>.  You can specify the
use of these devices for acquiring the seed for the PRNG when you declare
this module:

  use Math::Random::MT::Auto '/dev/urandom';
    # or
  my $prng = Math::Random::MT::Auto->new('SOURCE' => '/dev/random');

or they can be specified when using the L</"srand"> function.

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

  my $prng = Math::Random::MT::Auto->new(
                        'SOURCE' => ['hotbits',
                                     'hotbits' => 448 / $Config{'uvsize'}] );

=item Windows XP Random Data

Under Windows XP, you can acquire random seed data from the system.

  use Math::Random::MT::Auto 'win32';

To utilize this option, you must have the L<Win32::API> module
installed.

=back

The default list of seeding sources is determined when the module is loaded
(actually when the C<import> function is called).  Under Windows XP,
C<win32> is added to the list.  Otherwise, F</dev/urandom> and then
F</dev/random> are checked.  The first one found is added to the list.
Finally, C<random_org> is added.

For the functional interface to the standalone PRNG, these defaults can be
overridden by specifying the desired sources when the module is declared, or
through the use of the L</"srand"> function.  Similarly for the OO interface,
they can be overridden in the L</"$obj-E<gt>new"> method when the PRNG is
created, or later using the L<srand|/"$obj-E<gt>srand"> method.

Optionally, the maximum number of integers (64- or 32-bits as the case may
be) to be used from a source may be specified:

  # Get at most 2000 bytes from random.org
  # Finish the seed using data from /dev/urandom
  use Math::Random::MT::Auto 'random_org' => 2000 / $Config{'uvsize'},
                             '/dev/urandom';

(I would be interested to hear about other random data sources if they
could easily be included in future versions of this module.)

=head2 Functional Interface to the Standalone PRNG

By default, this module does not automatically export any of its functions.
If you want to use the standalone PRNG, then you should specify the
functions you want to use when you declare the module:

  use Math::Random::MT::Auto qw(rand irand shuffle gaussian
                                exponential erlang poisson binomial
                                srand get_warnings get_seed
                                set_seed get_state set_state);

Without the above declarations, it is still possible to use the standalone
PRNG by accessing the functions using their fully-qualified names.  For
example:

  my $rand = Math::Random::MT::Auto::rand();

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
I<half-life> is given by I<mean * ln(2)>.

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

  The number of decays from a radioactive sample within a given
    time period.
  The number of cars that pass a certain point on a road within
    a given time period.
  The number of phone calls to a call center per minute.
  The number of road kill found per a given length of road.

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

This (re)seeds the PRNG.  It should definitely be called when the
L<:!auto|/"Delayed Seeding"> option is used.  Additionally, it may be
called anytime reseeding of the PRNG is desired (although this should
normally not be needed).

When called without arguments, the previously determined/specified seeding
source(s) will be used to seed the PRNG.

Optionally, seeding sources may be supplied as arguments.  (These will be
saved and used again if L</"srand"> is subsequently called without
arguments).

  srand('hotbits', '/dev/random');

If called with a subroutine reference, then the subroutine will be called
to acquire the seeding data.  The subroutine will be passed two arguments:
A array reference where seed data is to be added, and the number of
integers (64- or 32-bit as the case may be) needed.

  sub MySeeder
  {
      my $seed = $_[0];
      my $need = $_[1];

      while ($need--) {
          my $data = ...;      # Get seed data from your source
          push(@$seed, $data);
      }
  }

  # Call MySeeder for 200 integers, and
  #  then get the rest from random.org.
  srand(\&MySeeder => 200, 'random_org');

If called with integer data (a list of one or more value, or an array of
values), or a reference to an array of integers, these data will be passed to
L</"set_seed"> for use in reseeding the PRNG.

NOTE: If you still need to access Perl's built-in L<srand|perlfunc/"srand">
function, you can do so using C<CORE::srand($seed)>.

=item get_warnings

  my @warnings = get_warnings();
  my @warnings = get_warnings('CLEAR');

This function returns an array containing any error messages that were
generated while trying to acquire seed data for the standalone PRNG.  It
can be called after the module is loaded, or after calling L</"srand"> to
see if there where any problems getting the seed.

If called with any I<true> argument, the stored error messages will also be
deleted.

B<NOTE>: These warnings are not critical in nature.  The PRNG will still be
seeded (at a minimum using data such as L<time()|perlfunc/"time"> and PID
(L<$$|perlvar/"$$">)), and can be used safely.

=item get_seed

  my $seed = get_seed();

This function will return an array reference containing the seed last sent to
the PRNG.

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

Together with L</"get_seed">, this function may be useful for setting up
identical sequences of random numbers based on the same seed.

=item get_state

  my $state = get_state();

This function returns an array reference containing the current state vector
of the PRNG.

Note that the state vector is not a full serialization of the PRNG, which
would also require information on the sources and seed.

=item set_state

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
feeding it to L</"set_state"> would be naughty.

In conjunction with L<Data::Dumper> and L<do(file)|perlfunc/"do">,
L</"get_state"> and L</"set_state"> can be used to save and then reload the
state vector between application runs.  (See L</"EXAMPLES"> below.)

=back

=head2 Delayed Seeding

Normally, the standalone PRNG is automatically seeded when the module is
loaded.  This behavior can be modified by supplying the C<:!auto> (or
C<:noauto>) flag when the module is declared.  (The PRNG will still be
seeded using data such as L<time()|perlfunc/"time"> and PID
(L<$$|perlvar/"$$">), just in case.)  When the C<:!auto> option is used, the
L</"srand"> function should be imported, and then run before calling any of
the random number deviates.

  use Math::Random::MT::Auto qw(rand srand :!auto);
    ...
  srand();
    ...
  my $rn = rand(10);

=head2 OO Interface

The OO interface for this module allows you to create multiple, independent
PRNGs.

=over

=item Math::Random::MT::Auto->new

  my $prng = Math::Random::MT::Auto->new( %options );

Creates a new PRNG.  With no options, the PRNG is seeded using the default
sources that were determined when the module was loaded.

=over

=item 'STATE' => $prng_state

Sets the newly created PRNG to the specified state.  The PRNG will then
function as a clone of the RPNG that the state was obtained from (at the
point when then state was obtained).

When the C<STATE> option is used, any other options are just stored (i.e.,
they are not acted upon).

=item 'SEED' => $seed_array_ref

When the C<STATE> option is not used, this options seeds the newly created
PRNG using the supplied seed data.  Otherwise, the seed data is just
copied to the new object.

=item 'SOURCE' => 'source'

=item 'SOURCE' => ['source', ...]

Specifies the seeding source(s) for the PRNG.  If the C<STATE> and C<SEED>
options are not used, then seed data will be immediately fetched using the
specified sources and used to seed the PRNG.

The source list is retained for later use by the L<srand|/"$obj-E<gt>srand">
method.  The source list may be replaced by using the
L<srand|/"$obj-E<gt>srand"> method.

'SOURCES', 'SRC' and 'SRCS' can all be used as synonyms for 'SOURCE'.

=back

The options above are also supported using lowercase and mixed-case (e.g.,
'Seed', 'src', etc.).

=item $obj->new

  my $prng2 = $prng1->new( %options );

Creates a new PRNG, optionally using attributes from the referenced PRNG.

With no options, the new PRNG will be a complete clone of the referenced
PRNG.

When the C<STATE> option is provided, it will be used to set the new PRNG's
state vector.  The referenced PRNG's seed is not copied to the new PRNG in
this case.

When provided, the C<SEED> and C<SOURCE> options behave as described above.

=item $obj->rand

  my $rn = $prng->rand();
  my $rn = $prng->rand($num);

Operates like the L</"rand"> function described above, returning a number
uniformly distributed in [0, $num).  ($num defaults to 1.)

=item $obj->irand

  my $int = $prng->irand();

Operates like the L</"irand"> function described above, returning a random
integer.  For 32-bit integer Perl, the range is 0 to 2^32-1 (0xFFFFFFFF)
inclusive.  For 64-bit integer Perl, it's 0 to 2^64-1 inclusive.

This is the fastest OO method for obtaining random numbers with this module.

=item $obj->shuffle

  my $shuffled = $prng->shuffle($data, ...);
  my $shuffled = $prng->shuffle(@data);
  my $shuffled = $prng->shuffle(\@data);

Operates like the L</"shuffle"> function described above, returning an array
reference containing a random ordering of the supplied arguments.  If called
with a single array reference (fastest method), the contents of the array are
shuffled in situ.

=item $obj->gaussian

  my $gn = $prng->gaussian();
  my $gn = $prng->gaussian($sd);
  my $gn = $prng->gaussian($sd, $mean);

Operates like the L</"gaussian"> function described above, returning
floating-point random numbers from a Gaussian (normal) distribution.  The
standard deviation defaults to 1 and the mean defaults to 0.

=item $obj->exponential

  my $xn = $prng->exponential();
  my $xn = $prng->exponential($mean);

Operates like the L</"exponential"> function described above, returning
floating-point random numbers from an exponential distribution.  The mean
defaults to 1.

=item $obj->erlang

  my $en = $prng->erlang($order);
  my $en = $prng->erlang($order, $mean);

Operates like the L</"erlang"> function described above, returning
floating-point random numbers from an Erlang distribution of specified integer
order (> 0).  The mean, if not specified, defaults to 1.

=item $obj->poisson

  my $pn = $prng->poisson($mean);
  my $pn = $prng->poisson($rate, $time);

Operates like the L</"poisson"> function described above, returning integer
random numbers (>= 0) from a Poisson distribution of specified mean (rate *
time = mean).  The mean must be a positive value (> 0).

=item $obj->binomial

  my $bn = $prng->binomial($prob, $trials);

Operates like the L</"binomial"> function described above, returning integer
random numbers (>= 0) from a binomial distribution.  The probability
(C<$prob>) must be between 0.0 and 1.0 (inclusive), and the number of trials
must be >= 0.

=item $obj->srand

  $prng->srand();
  $prng->srand('source', ...);

Operates like the L</"srand"> function described above, reseeding the PRNG.

When called without arguments, the previously-used seeding source(s) will
be accessed.

Optionally, seeding sources may be supplied as arguments.  (These will be
saved and used again if the L<srand|/"$obj-E<gt>srand"> method is subsequently
called without arguments).

If called with integer data (a list of one or more value, or an array of
values), or a reference to an array of integers, these data will be passed to
the L<set_seed|/"$obj-E<gt>set_seed"> method for use in reseeding the PRNG.

=item $obj->get_warnings

  my @warnings = $prng->get_warnings();
  my @warnings = $prng->get_warnings('CLEAR');

Operates like the L</"get_warnings"> function described above, retrieving any
error messages that were generated while trying to acquire seed data for
the PRNG.  It can be called after the object is created, or after calling
the L<srand|/"$obj-E<gt>srand"> method to see if there where any problems
getting the seed.

If called with any I<true> argument, the stored error messages will also be
deleted.

=item $obj->get_seed

  my $seed = $prgn->get_seed();

Operates like the L</"get_seed"> function described above, retrieving the
PRNG's seed.

If the PRNG object was created from another PRNG object using the
L<STATE|/"'STATE' =E<gt> $prng_state"> option, then this method may return
C<undef>.

=item $obj->set_seed

  $prgn->set_seed($seed, ...);
  $prgn->set_seed(@seed);
  $prgn->set_seed(\@seed);

Operates like the L</"set_seed"> function described above, setting the PRNG
to the supplied seed.

=item $obj->get_state

  my $state = $prgn->get_state();

Operates like the L</"get_state"> function described above, retrieving the
PRNG's state.

=item $obj->set_state

  $prgn->set_state($state);

Operates like the L</"set_state"> function described above, setting the PRNG
to the supplied state.

=back

=head2 Thread Support

This module is thread-safe for PRNGs created through the OO interface for
Perl v5.7.2 and beyond.

For Perl prior to v5.7.2, the PRNG objects created in the parent will be
I<broken> in the thread once it is created.  Therefore, new PRNG objects must
be created in the thread.

The standalone PRNG is not thread-safe, and hence should not be used in
threaded applications.

I<No object sharing between threads>

Due to limitations in the Perl threading model, I<blessed> objects (i.e.,
objects create through OO interfaces) cannot be shared between threads.  The
L<docs on this|threads::shared/"BUGS"> are not worded very clearly, but here's
the gist:

=over

When a thread is created, any I<blessed> objects that exist will be cloned
between the parent and child threads such that the two copies of the object
then function independent of one another.

However, the threading model does not support sharing I<blessed> objects
(via L<use threads::shared|threads::shared>) between threads such that an
object appears to be a single copy whereby changes to the object made in the
one thread are visible in another thread.

=back

Thus, the following will generate a runtime error:

  use Math::Random::MT::Auto;
  use threads;
  use threads::shared;

  my $prng;
  share($prng);

  $prng = Math::Random::MT::Auto->new();

and if you try turning things around a bit:

  my $prng = Math::Random::MT::Auto->new();
  share($prng);

you don't get an error message, but all the I<internals> of your object
are wiped out.  (In this case C<$prng> is now just a reference to an empty
hash - the data placed inside it when it was created have been removed.)

(Just to be perfectly clear:  This is not a deficiency in this module,
but an issue with Perl's threading model in general.)

=head2 Delayed Importation

If you want to delay the importation of this module using
L<require|perlfunc/"require">, then you need to execute its C<import> function
to complete the module's initialization:

  eval {
      require Math::Random::MT::Auto;
      # Add symbols to the import call, as desired.
      import Math::Random::MT::Auto qw(rand random_org);
  };

=head2 Implementing Subclasses

This package uses the I<inside-out> object model (see informational links
under L</"SEE ALSO">).  This object model offers a number of advantages, but
does require some extra programming when you create subclasses so as to
support (among other things) oject cloning for thread safety (i.e., a CLONE
subroutine), and oject destruction (i.e., a DESTROY subroutine).

Further, the objects created are not the usual blessed hash reference: In the
case of this package, they are blessed scalar references.  Therefore, your
subclass cannot store attributes I<inside> the object returned by this
package, nor should you modify or make use of the value stored in the object's
referenced scalar.

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
of pseudo-random numbers.

=item Save state to file

  use Data::Dumper;
  use Math::Random::MT::Auto qw(rand irand get_state);

  my $state = get_state();
  if (open(my $FH, '>/tmp/rand_state_data.tmp')) {
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

This module sets a 10 second timeout for Internet connections so that if
something goes awry when trying to get seed data from an Internet source,
your application will not hang for an inordinate amount of time.

If you connect to the Internet through an HTTP proxy, then you must set the
L<http_proxy|LWP/"http_proxy"> variable in your environment when using the
Internet seed sources.  (See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site has a quota on the amount of data you can request in a
24-hour period.  (I don't know how big the quota is.)  Therefore, this
source may fail to provide any data if used too often.

If the module cannot acquire any seed data from the specified sources, then
data such as L<time()|perlfunc/"time"> and PID (L<$$|perlvar/"$$">) will be
used to seed the PRNG.  Use L</"get_warnings"> to check for seed acquisition
problems.

It is possible to seed the PRNG with more than 19968 bits of data (through
the use of a seeding subroutine supplied to L</"srand">, or by supplying a
large array ref of data to L</"set_seed">).  However, doing so does not make
the PRNG "more random" as 19968 bits more than covers all the possible PRNG
state vectors.

=head1 PERFORMANCE

Under Windows, this module is more than twice as fast as Math::Random::MT, and
under Solaris, it's more than four times faster.  The file
F<samples/timings.pl>, included in this module's distribution, can be used to
compare timing results.

If you connect to the Internet via a phone modem, acquiring seed data may take
a second or so.  This delay might be apparent when your application is first
started, or after creating a new PRNG object.  This is especially true if you
specify the L<hotbits|/"Internet Sites"> source twice (so as to get the full
seed from the HotBits site) as this results in two accesses to the Internet.
(If F</dev/urandom> is available on your machine, then you should definitely
consider using the Internet sources only as a secondary source.)

=head1 SEE ALSO

The Mersenne Twister is the (current) quintessential pseudo-random number
generator. It is fast, and has a period of 2^19937 - 1.  The Mersenne
Twister algorithm was developed by Makoto Matsumoto and Takuji Nishimura.
It is available in 32- and 64-bit integer versions.
L<http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>

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
L<http://www.perlmonks.org/index.pl?node_id=483162>, and
Chapter 15 of I<Perl Best Practices> by Damian Conway

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
