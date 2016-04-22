package Math::Random::MT::Auto;

use strict;
use warnings;

use 5.006;   # 64-bit support
use Config;
use Scalar::Util qw/looks_like_number weaken/;

require DynaLoader;
our @ISA = qw(DynaLoader);

our $VERSION = 1.33;

bootstrap Math::Random::MT::Auto $VERSION;

### Global Variables ###

# Default seeding sources (set up in import())
my @SOURCE;

# Standalone PRNG data
my %STANDALONE = (
    'PRNG'   => SA_prng(),      # Reference to the PRNG
    'SOURCE' => \@SOURCE,       # Uses global defaults sources
    'SEED'   => [],             # Last seed sent to PRNG
    'WARN'   => [],             # Error messages
    'AUTO'   => 1               # Flag to auto-seed PRNG during INIT block
);

# Maintains weak references to PRNG objects for thread cloning
my @CLONING_LIST;


### Module Initialization ###

# 1. Size of Perl's integers
my $INT_SIZE = $Config{'uvsize'};
my $UNPACK_CODE = ($INT_SIZE == 8) ? 'Q' : 'L';


# 2. Handles importation of random functions,
# and specification of seeding sources by user.
sub import
{
    my $class = shift;
    my $pkg = caller;

    while (my $sym = shift) {
        # Exportable functions
        if ($sym eq 'irand' || $sym eq 'rand') {
            no strict 'refs';
            *{"${pkg}::$sym"} = \&{"mt_$sym"};

        } elsif ($sym eq 'srand'    ||
                 $sym eq 'seed'     ||
                 $sym eq 'state'    ||
                 $sym eq 'warnings' ||
                 $sym eq 'gaussian' ||
                 $sym eq 'rand32')
        {
            no strict 'refs';
            *{"${pkg}::$sym"} = \&$sym;

        } elsif ($sym =~ /(no|!)?auto/) {
            # To auto-seed or not
            $STANDALONE{'AUTO'} = not defined($1);

        } else {
            # User-specified seed acquisition sources
            # or user-defined seed acquisition functions
            push(@SOURCE, $sym);
            # Max. count for source, if any
            if (@_ && looks_like_number($_[0])) {
                push(@SOURCE, shift(@_));
            }
        }
    }

    # Set up default seed sources, if none specified by user
    if (! @SOURCE) {
        if ($^O eq 'MSWin32') {
            my ($id, $major, $minor) = (Win32::GetOSVersion())[4,1,2];
            if (defined($minor) &&
                (($id > 2) ||
                 ($id == 2 && $major > 5) ||
                 ($id == 2 && $major == 5 && $id >= 1)))
            {
                push(@SOURCE, 'win32');
            }

        } elsif (-e '/dev/urandom') {
            push(@SOURCE, '/dev/urandom');

        } elsif (-e '/dev/random') {
            push(@SOURCE, '/dev/random');
        }
        push(@SOURCE, 'random_org');
    }
}


# 3. Auto seed the standalone PRNG after the module is loaded.
# Even when $STANDALONE{'AUTO'} is false, the PRNG is still seeded
# using time and PID.
{
    no warnings;
    INIT {
        # Automatically acquire seed from sources
        _acq_seed(($STANDALONE{'AUTO'}) ? $STANDALONE{'SOURCE'} : ['none'],
                  $STANDALONE{'SEED'},
                  $STANDALONE{'WARN'});
        # Seed the PRNG
        X_seed($STANDALONE{'PRNG'}, $STANDALONE{'SEED'});
    }
}


### Thread Cloning Support ###

# Called before thread cloning starts
# Supported in 5.8.7 and later
sub CLONE_SKIP
{
    # Save state for each PRNG object
    foreach my $self (@CLONING_LIST) {
        if ($self) {
            $self->{'STATE'} = X_get_state($self->{'PRNG'});
        }
    }

    # Indicate that CLONE should be called
    return (0);
}


# Called after thread is cloned
sub CLONE
{
    foreach my $self (@CLONING_LIST) {
        if ($self) {
            # Create new memory for each PRNG object
            $self->{'PRNG'} = OO_prng();

            if (exists($self->{'STATE'})) {
                # Restore state, if present
                X_set_state($self->{'PRNG'}, $self->{'STATE'});

            } else {
                # Acquire seed, if none provided
                if (! exists($self->{'SEED'})) {
                    $self->{'SEED'} = [];
                    _acq_seed($self->{'SOURCE'}, $self->{'SEED'}, $self->{'WARN'});
                }

                # Seed the PRNG
                X_seed($self->{'PRNG'}, $self->{'SEED'});
            }
        }
    }
}


### Dual-Interface Subroutines ###

# Starts PRNG with random seed using specified sources (if any)
sub srand
{
    my $self;

    # Generalize for both OO and standalone PRNGs
    my $obj;
    if (defined($_[0]) &&
        UNIVERSAL::isa($_[0], 'UNIVERSAL') &&
        $_[0]->isa(__PACKAGE__))
    {
        # OO interface
        $obj = $self = shift;
    } else {
        # Standalone PRNG
        $obj = \%STANDALONE;
    }

    if (@_) {
        # Check if sent seed by mistake
        if (looks_like_number($_[0]) || ref($_[0]) eq 'ARRAY') {
            if ($self) {
                $self->seed(@_);
            } else {
                seed(@_);
            }
            return;
        }

        # Save specified sources
        @{$obj->{'SOURCE'}} = @_;
    }

    # Acquire seed from sources
    _acq_seed($obj->{'SOURCE'}, $obj->{'SEED'}, $obj->{'WARN'});
    # Seed the PRNG
    X_seed($obj->{'PRNG'}, $obj->{'SEED'});
}


# Use supplied seed, if given
# Returns ref to saved seed if no args
sub seed
{
    # Generalize for both OO and standalone PRNGs
    my $obj;
    if (defined($_[0]) &&
        UNIVERSAL::isa($_[0], 'UNIVERSAL') &&
        $_[0]->isa(__PACKAGE__))
    {
        # OO interface
        $obj = shift;
    } else {
        # Standalone PRNG
        $obj = \%STANDALONE;
    }

    # User requested the seed
    if (! @_) {
        return ($obj->{'SEED'});
    }

    # Save a copy of the seed
    if (ref($_[0]) eq 'ARRAY') {
        @{$obj->{'SEED'}} = @{$_[0]};
    } else {
        @{$obj->{'SEED'}} = @_;
    }

    # Seed the PRNG
    X_seed($obj->{'PRNG'}, $obj->{'SEED'});
}


# Set PRNG to supplied state, if given,
# or return copy of PRNG's current state
sub state
{
    # Generalize for both OO and standalone PRNGs
    my $obj;
    if (defined($_[0]) &&
        UNIVERSAL::isa($_[0], 'UNIVERSAL') &&
        $_[0]->isa(__PACKAGE__))
    {
        # OO interface
        $obj = shift;
    } else {
        # Standalone PRNG
        $obj = \%STANDALONE;
    }

    # Set state of PRNG, if supplied
    if (@_) {
        X_set_state($obj->{'PRNG'}, $_[0]);
        return;
    }

    # User requested copy of state
    return (X_get_state($obj->{'PRNG'}));
}


# Returns ref to PRNG's warnings array
sub warnings
{
    # Generalize for both OO and standalone PRNGs
    my $obj;
    if (defined($_[0]) &&
        UNIVERSAL::isa($_[0], 'UNIVERSAL') &&
        $_[0]->isa(__PACKAGE__))
    {
        # OO interface
        $obj = shift;
    } else {
        # Standalone PRNG
        $obj = \%STANDALONE;
    }

    # If arg is true, then send warnings and clear the warnings array
    if ($_[0]) {
        my @warnings = @{$obj->{'WARN'}};
        $obj->{'WARN'} = [];
        return (@warnings);
    }

    # Just send a copy of the warnings
    return (@{$obj->{'WARN'}});
}


# Gaussian probability
sub gaussian
{
    # Generalize for both OO and standalone PRNGs
    my $obj;
    if (defined($_[0]) &&
        UNIVERSAL::isa($_[0], 'UNIVERSAL') &&
        $_[0]->isa(__PACKAGE__))
    {
        # OO interface
        $obj = shift;
    } else {
        # Standalone PRNG
        $obj = \%STANDALONE;
    }

    return ((@_) ? X_gaussian($obj->{'PRNG'}, $_[0])
                 : X_gaussian($obj->{'PRNG'}));
}


### OO Methods ###

# Create a new PRNG object
sub new
{
    my $thing = shift;
    my $class = ref($thing) || $thing;
    my $self = {};
    bless($self, $class);
    if (! $self->_init($thing, @_)) {
        return;   # Failed to initialize
    }
    return ($self);
}


# Initialize a new PRNG object
sub _init
{
    my $self  = shift;
    my $thing = shift;

    # Initialize with any user-supplied data
    my $no_args = 1;
    while (my $key = shift) {
        $self->{$key} = shift;
        $no_args = 0;
    }

    # - Fix user-supplied data -
    # Convert all keys to uppercase
    foreach my $key (keys(%$self)) {
        if (! exists($self->{uc($key)})) {
            $self->{uc($key)} = $self->{$key};
            delete($self->{$key});
        }
    }
    # Change 'SOURCES' to 'SOURCE'
    if (exists($self->{'SOURCES'})) {
        $self->{'SOURCE'} = $self->{'SOURCES'};
        delete($self->{'SOURCES'});
    }
    # Turn 'SOURCE' into an array ref
    if (exists($self->{'SOURCE'}) && ref($self->{'SOURCE'}) ne 'ARRAY') {
        $self->{'SOURCE'} = [ $self->{'SOURCE'} ];
    }

    # Further initializations
    $self->{'PRNG'} = OO_prng();
    $self->{'WARN'} = [];

    if (ref($thing)) {
        # $thing->new(...) was called
        if ($no_args) {
            # $thing->new() called with no args - 'clone' the PRNG
            @{$self->{'SOURCE'}} = @{$thing->{'SOURCE'}};
            if (exists($thing->{'SEED'})) {
                @{$self->{'SEED'}} = @{$thing->{'SEED'}};
            }
            $self->{'STATE'} = X_get_state($thing->{'PRNG'});

        } else {
            # Copy object's sources, if none provided
            if (! exists($self->{'SOURCE'})) {
                @{$self->{'SOURCE'}} = @{$thing->{'SOURCE'}};
            }
        }

    } else {
        # CLASS->new(...) was called
        # Use default sources, if none provided
        if (! exists($self->{'SOURCE'})) {
            @{$self->{'SOURCE'}} = @SOURCE;
        }
    }

    # If state is specified, then use it
    if (exists($self->{'STATE'})) {
        X_set_state($self->{'PRNG'}, $self->{'STATE'});
        delete($self->{'STATE'});

    } else {
        # Acquire seed, if none provided
        if (! exists($self->{'SEED'})) {
            $self->{'SEED'} = [];
            _acq_seed($self->{'SOURCE'}, $self->{'SEED'}, $self->{'WARN'});
        }

        # Seed the PRNG
        X_seed($self->{'PRNG'}, $self->{'SEED'});
    }

    # Save copy of reference for thread cloning
    my $ii;
    for ($ii=0; $ii < @CLONING_LIST; $ii++) {
        if (! defined($CLONING_LIST[$ii])) {
            last;
        }
    }
    $CLONING_LIST[$ii] = $self;
    weaken($CLONING_LIST[$ii]);

    return (1);
}


# Object cleanup
sub DESTROY
{
    if (ref($_[0]) eq 'HASH' && exists($_[0]->{'PRNG'})) {
        OO_DESTROY($_[0]->{'PRNG'});
        delete($_[0]->{'PRNG'});
    }
}


### DEPRECATED ###

# Random 32-bit ints
sub rand32
{
    # OO interface
    if (defined($_[0]) &&
        UNIVERSAL::isa($_[0], 'UNIVERSAL') &&
        $_[0]->isa(__PACKAGE__))
    {
        return ($_[0]->irand() & 0xFFFFFFFF);
    }

    # Standalone PRNG
    return (mt_irand() & 0xFFFFFFFF);
}


# Random 32-bit ints
sub mt_rand32
{
    # Standalone PRNG
    return (mt_irand() & 0xFFFFFFFF);
}



### Internal Subroutines ###

my %_acq_dispatch = (
    'random_org' => \&_acq_random_org,
    'hotbits'    => \&_acq_hotbits,
    'win32'      => \&_acq_win32
);

# Acquire seed data from specifiec sources
sub _acq_seed
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

        } elsif ($source ne 'none') {
            if (defined($_acq_dispatch{$source})) {
                # Module defined seeding source
                $_acq_dispatch{$source}($seed, $need, $warnings);

            } elsif (-e $source) {
                # Random device or file
                _acq_dev($source, $seed, $need, $warnings);

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
        } elsif ($$sources[0] ne 'none') {
            push(@$warnings, 'Partial seed - only ' . scalar(@$seed) . ' of ' . $FULL_SEED);
        }
        if (! @$seed) {
            push(@$seed, time(), $$);  # Default seed
        }
    }
}


# Acquire seed data from a device/file
sub _acq_dev
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

    # Set non-blocking mode
    eval { use Fcntl; };
    if ($@) {
        close($FH);
        push(@$warnings, "Failure importing Fcntl module: $@");
        return;
    }
    my $flags = 0;
    if (! fcntl($FH, F_GETFL, $flags)) {
        push(@$warnings, "Failure getting filehandle flags: $!");
        close($FH);
        return;
    }
    $flags |= O_NONBLOCK;
    if (! fcntl($FH, F_SETFL, $flags)) {
        push(@$warnings, "Failure setting filehandle flags: $!");
        close($FH);
        return;
    }

    # Read data
    my $data;
    my $cnt = read($FH, $data, $bytes);
    close($FH);
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
sub _acq_random_org
{
    my $seed     = $_[0];
    my $need     = $_[1];
    my $warnings = $_[2];
    my $bytes    = $need * $INT_SIZE;

    # Load LWP::UserAgent module
    eval {
        require LWP::UserAgent;
        import LWP::UserAgent;
    };
    if ($@) {
        push(@$warnings, "Failure importing LWP::UserAgent: $@");
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
        push(@$seed, unpack("$UNPACK_CODE*", $res->content));
    } else {
        push(@$warnings, 'Failure getting data from random.org: '
                            . $res->status_line);
    }
}


# Acquire seed data from HotBits
sub _acq_hotbits
{
    my $seed     = $_[0];
    my $need     = $_[1];
    my $warnings = $_[2];
    my $bytes    = $need * $INT_SIZE;

    # Load LWP::UserAgent module
    eval {
        require LWP::UserAgent;
        import LWP::UserAgent;
    };
    if ($@) {
        push(@$warnings, "Failure importing LWP::UserAgent: $@");
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
            push(@$seed, unpack("$UNPACK_CODE*", $res->content));
        }
    } else {
        push(@$warnings, 'Failure getting data from HotBits: '
                            . $res->status_line);
    }
}


# Acquire seed data from HotBits
sub _acq_win32
{
    my $seed     = $_[0];
    my $need     = $_[1];
    my $warnings = $_[2];
    my $bytes    = $need * $INT_SIZE;

    # Load Win32::API::Prototype module
    eval {
        require Win32::API::Prototype;
        import Win32::API::Prototype;
    };
    if ($@) {
        push(@$warnings, "Failure importing Win32::API::Prototype: $@");
        return;
    }

    # Acquire the random number function
    if (! ApiLink('ADVAPI32.DLL', 'BOOLEAN SystemFunction036(PVOID b, ULONG n)')) {
        push(@$warnings, "Failure acquiring Win32 random function: $^E");
        return;
    }

    # Acquire the random data
    my $buffer = chr(0) x $bytes;
    if (SystemFunction036($buffer, $bytes)) {
        push(@$seed, unpack("$UNPACK_CODE*", $buffer));
    } else {
        push(@$warnings, "Failure acquiring Win32 seed data: $^E");
    }
}

1;

__END__

=head1 NAME

Math::Random::MT::Auto - Auto-seeded Mersenne Twister PRNG

=head1 SYNOPSIS

  use Math::Random::MT::Auto qw/rand irand gaussian/,
                             '/dev/urandom' => 256,
                             'random_org';

  # Functional interface
  my $die_roll = 1 + int(rand(6));

  my $coin_flip = (irand() & 1) ? 'heads' : 'tails';

  my $rand_IQ = 100 + gaussian(15);

  # OO interface
  my $prng = Math::Random::MT::Auto->new('SOURCE' => '/dev/random');

  my $angle = $prng->rand(360);

  my $rand_height = 69 + $prng->gaussian(3);

=head1 DESCRIPTION

The Mersenne Twister is a fast pseudo-random number generator (PRNG) that
is capable of providing large volumes (> 10^6004) of "high quality"
pseudo-random data to applications that may exhaust available "truly"
random data sources or system-provided PRNGs such as
L<rand|perlfunc/"rand">.

This module provides PRNGs that are based on the Mersenne Twister.  There
is a functional interface to a single, standalone PRNG, and an OO interface
for generating multiple PRNG objects.  The PRNGs are self-seeding,
automatically acquiring a (19968-bit) random seed from user-selectable
sources.

This module is thread-safe with respect to its OO interface for Perl v5.7.2
and beyond.  The standalone PRNG is not thread-safe.

For Perl compiled to support 64-bit integers, this module will use a 64-bit
version of the Mersenne Twister algorithm, thus providing 64-bit random
integers (and 53-bit random doubles).  (32-bits otherwise.)

The code for this module has been optimized for speed.  Under Windows, it's
2.5 times faster than Math::Random::MT for the functional interface, and 2
times faster for the OO interface.  Under Solaris, it's 4x and 3.5x faster,
respectively.

=head2 Quickstart

To use this module as a drop-in replacement for Perl's
L<rand|perlfunc/"rand"> function, just add the following to the top of your
application code:

  use Math::Random::MT::Auto qw/rand/;

and then just use L</"rand"> as you would normally.  You don't even need to
bother seeding the PRNG (i.e., you don't need to call L</"srand">), as that
gets done automatically when the module is loaded by Perl.

If you need multiple PRNGs, then use the OO interface:

  use Math::Random::MT::Auto;

  my $prng1 = Math::Random::MT::Auto->new();
  my $prng2 = Math::Random::MT::Auto->new();

  my $rand_num = $prng1->rand();
  my $rand_int = $prng2->irand();

B<CAUTION>: If you want to C<require> this module, see the
L</"Delayed Importation"> section for important information.

=head2 64-bit Support

If Perl has been compiled to support 64-bit integers (do C<perl -V> and
look for C<use64bitint=define>), then this module will use a 64-bit-integer
version of the Mersenne Twister.  Otherwise, 32-bit integers will be used.
The size of integers returned by L</"irand">, and used by L</"seed"> will
be sized accordingly.

Programmatically, the size of Perl's integers can be determined using the
L<Config> module:

  use Config;

  print("Ints are $Config{'uvsize'} bytes in length\n");

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
the C<http_proxy> variable in your environment when using this source.
(See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site will only provide a maximum of 2048 bytes of data per
request.  If you want to get the full seed from HotBits, then specify
the C<hotbits> source twice in the module declaration.

  my $prng = Math::Random::MT::Auto->new(
                        'SOURCE' => ['hotbits',
                                     'hotbits' => 448 / $Config{'uvsize'}] );

=item Windows XP Random Data

On Windows XP, you can acquire random seed data from the system.

  use Math::Random::MT::Auto 'win32';

To utilize this option, you must have the L<Win32::API::Prototype> module
installed.

=back

The default list of seeding sources is determined when the module is loaded
(actually when the C<import> function is called).  On Windows XP, C<win32>
is added to the list.  Otherwise, F</dev/urandom> and then F</dev/random>
are checked.  The first one found is added to the list.  Finally,
C<random_org> is added.

For the functional interface to the standalone PRNG, these defaults can be
overriden by specifying the desired sources when the module is declared, or
through the use of the L</"srand"> function.  Similarly for the OO interface,
they can be overridden in the L</"new"> method when the PRNG is created, or
later using the L</"srand"> method.

Optionally, the maximum number of integers (64- or 32-bits as the case may
be) to be used from a source may be specified:

  # Get at most 2000 bytes from random.org
  # Finish the seed using data from /dev/urandom
  use Math::Random::MT::Auto 'random_org' => 2000 / $Config{'uvsize'},
                             '/dev/urandom';

(I would be interested to hear about other random data sources if they
could easily be included in future versions of this module.)

=head2 Functional Interface to the Standalone PRNG

The functional interface to the standalone PRNG is faster than the OO
interface for obtaining pseudo-random numbers.

By default, this module does not automatically export any of its functions.
If you want to use the standalone PRNG, then you should specify the
functions you want to use when you declare the module:

  use Math::Random::MT::Auto
            qw/rand irand gaussian srand seed state warnings/;

Without the above declarations, it is still possible to use the standalone
PRNG by accessing the functions using their full module paths, as described
below.

=over

=item rand

 my $rn = rand();
 my $rn = rand($num);

Behaves exactly like Perl's built-in L<rand|perlfunc/"rand">, returning a
number uniformly distributed in [0, $num).  ($num defaults to 1.)

This function may also be accessed using the full path
C<Math::Random::MT::Auto::mt_rand> (note the I<mt_> prefix).  (NOTE: If you
still need to access Perl's built-in L<rand|perlfunc/"rand"> function, you
can do so using C<CORE::rand()>.)

=item irand

  my $int = irand();

Returns a random integer.  For 32-bit integer Perl, the range is 0 to
2^32-1 (0xFFFFFFFF) inclusive.  For 64-bit integer Perl, it's 0 to 2^64-1
inclusive.  This is the fastest method for obtaining pseudo-random numbers
with this module.

This function may also be accessed using the full path
C<Math::Random::MT::Auto::mt_irand> (note the I<mt_> prefix).

=item rand32  [DEPRECATED]

Returns a random 32-bit integer.  Provided for backwards compatibility.

=item gaussian

  my $gn = gaussian();
  my $gn = gaussian($num);

Returns floating-point random numbers from a Guassian (normal) distribution
(i.e., numbers that fit a bell curve) distributed about 0.  If called with
no arguments, the distribution uses a standard deviation of 1.  Otherwise,
the supplied argument will be used for the standard deviation.

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

If called with integer data (single value or an array), or a reference to
an array of integers, these data will be passed to L</"seed"> for use in
reseeding the PRNG.

This function may also be accessed using the full path
C<Math::Random::MT::Auto::srand>.  (NOTE: If you still need to access
Perl's built-in L<srand|perlfunc/"srand"> function, you can do so using
C<CORE::srand($seed)>.)

=item seed

  my $seed = seed();
  seed($seed);
  seed(@seed);
  seed(\@seed);

When called without arguments, this function will return an array reference
containing the seed last sent to the PRNG.  NOTE: Changing the data in the
referenced array will not cause any changes in the PRNG (i.e., it will not
reseed it).

When called with integer data (single value or an array), or a reference to
an array of integers, these data will be used to reseed the PRNG.

Together, this function may be useful for setting up identical sequences
of random numbers based on the same seed.

This function may also be accessed using the full path
C<Math::Random::MT::Auto::seed>.

=item state

  my $state = state();
  state($state);

When called without arguments, this function returns an array reference
containing the current state vector of the PRNG.

To reset the PRNG to a previous state, call this function with a previously
obtained state-vector array reference.

  # Get the current state of the PRNG
  my $state = state();

  # Run the PRNG some more
  my $rand1 = irand();

  # Restore the previous state of the PRNG
  state($state);

  # Get another random number
  my $rand2 = irand();

  # $rand1 and $rand2 will be equal.

B<CAUTION>:  It should go without saying that you should not modify the
values in the state vector, but I'll say it anyway: "You should not modify
the values in the state vector."  'Nough said.

This function may also be accessed using the full path
C<Math::Random::MT::Auto::state>.

In conjunction with L<Data::Dumper> and L<do(file)|perlfunc/"do">, this
function can be used to save and then reload the state vector between
application runs.  (See L</"EXAMPLES"> below.)

=item warnings

  my @warnings = warnings();
  my @warnings = warnings(1);

This function returns an array containing any error messages that were
generated while trying to acquire seed data for the standalone PRNG.  It
can be called after the module is loaded, or after calling L</"srand"> to
see if there where any problems getting the seed.

If called with a I<true> argument, the stored error messages will also be
erased.

This function may also be accessed using the full path
C<Math::Random::MT::Auto::warnings>.

=back

=head2 Delayed Seeding

Normally, the standalone PRNG is automatically seeded when the module is
loaded.  This behavior can be modified by supplying the C<:!auto> (or
C<:noauto>) flag when the module is declared.  (The PRNG will still be
seeded using time and PID just in case.)  When the C<:!auto> option is
used, the L</"srand"> function should be imported, and then run before
calling L</"rand"> or L</"irand">.

  use Math::Random::MT::Auto qw/rand srand :!auto/;
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
copied to the new opject.

=item 'SOURCE' => 'source'

=item 'SOURCE' => ['source', ...]

Specifies the seeding source(s) for the PRNG.  If the C<STATE> and C<SEED>
options are not used, then seed data will be immediately fetched using the
specified sources and used to seed the PRNG.

The source list is retained for later use with the C<seed> method.  The
source list may be replaced by using the C<srand> method.

=back

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

Behaves like Perl's built-in L<rand|perlfunc/"rand">, returning a number
uniformly distributed in [0, $num).  ($num defaults to 1.)

=item $obj->irand

  my $int = $prng->irand();

Returns a random integer.  For 32-bit integer Perl, the range is 0 to
2^32-1 (0xFFFFFFFF) inclusive.  For 64-bit integer Perl, it's 0 to 2^64-1
inclusive.  This is the fastest method for obtaining pseudo-random numbers

=item $obj->rand32  [DEPRECATED]

Returns a random 32-bit integer.  Provided for backwards compatibility.

=item $obj->gaussian

  my $gn = $prng->gaussian();
  my $gn = $prng->gaussian($num);

Operates like the L</"gaussian"> function described above, returning
floating-point random numbers from a Guassian (normal) distribution
distributed about 0 and having a standard deviation of 1 (no args), or
C<$num>.

=item $obj->srand

  $prng->srand();
  $prng->srand('source', ...);

Operates like the L</"srand"> function described above, reseeding the PRNG.

When called without arguments, the previously-used seeding source(s) will
be accessed.

Optionally, seeding sources may be supplied as arguments.  (These will be
saved and used again if the C<srand> method is subsequently called without
arguments).

If called with integer data (single value or an array), or a reference to
an array of integers, these data will be passed to the C<seed> method for
use in reseeding the PRNG.

=item $obj->seed

  my $seed = $prgn->seed();
  $prgn->seed($seed);
  $prgn->seed(@seed);
  $prgn->seed(\@seed);

Operates like the L</"seed"> function described above, retrieving the
PRNG's seed, or setting the PRNG to the supplied seed.

If the PRNG object was created from another PRNG object using the C<STATE>
option, then this method may return C<undef>.

=item $obj->state

  my $state = $prgn->state();
  $prgn->state($state);

Operates like the L</"state"> function described above, retrieving the
PRNG's state, or setting the PRNG to the supplied state.

=item $obj->warnings

  my @warnings = $prng->warnings();
  my @warnings = $prng->warnings(1);

Operates like the L</"warnings"> function described above, retrieving any
error messages that were generated while trying to acquire seed data for
the PRNG.  It can be called after the object is created, or after calling
the L</"srand"> method to see if there where any problems getting the seed.

If called with a I<true> argument, the stored error messages will also be
erased.

=back

=head2 Thread Support

This module is thread-safe for PRNGs created through the OO interface for
Perl v5.7.2 and beyond.

For Perl v5.8.7 and later, when a thread is created, any PRNG objects are
cloned:  A parent's PRNG object and its child's cloned copy will work
independently from one another, and will return identical random numbers
from the point of cloning.

For v5.7.2 through v5.8.6, when a thread is created, any PRNG objects are
carried over to the new thread, but they are not cloned.  Cloning can be
accomplished with the following workaround:  Prior to calling
C<threads->create()>, execute the following for every PRNG object to be
used inside the thread:

  $prng->{'STATE'} = $prng->state();

When the C<STATE> attribute is found (after the thread is created), it is
used to make the thread's copy of the PRNG a clone of the parent's.  If not
found, then the thread's copy of the PRNG is re-seeded either with the
existing C<SEED> attribute if found, or with a newly acquired seed.

Prior to v5.7.2, the PRNG objects created in the parent will be I<broken>
in the thread once it is created.  Therefore, new PRNG objects must be
created in the thread.

The standalone PRNG, however, is not thread-safe, and hence should not be
used in threaded applications.

B<NOTE>: Due to limitations in the Perl threading model, I<blessed> objects
(i.e., objects create through OO interfaces) cannot be shared between
threads.  The L<docs on this|threads::shared/"BUGS"> are not worded very
clearly, but here's the gist:

=over

When a thread is created, any I<blessed> objects that exist will be cloned
between the parent and child threads such that the two copies of the object
then function independent of one another.

However, the threading model does not support sharing I<blessed> objects
(via C<use threads::shared>) between threads such that an object appears to
be a single copy whereby changes to the object made in the one thread are
visible in another thhread.

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

When this module is imported via C<use>, the standalone PRNG is initialized
via an C<INIT> block that is executed right after the module is loaded.

However, if you want to delay the importation of this module using
C<require> and want to use the standlone PRNG, then you must import
L</"srand">, and execute it so that the PRNG gets initialized:

  eval {
      require Math::Random::MT::Auto;
      # Add other symbols to the import call, as desired.
      import Math::Random::MT::Auto qw/srand/;
      # Add seed sources to the srand() call, as desired.
      srand();
  };

If you're only going to use the OO interface, then the following is
sufficient:

  eval {
      require Math::Random::MT::Auto;
      # Add seed sources to the import call, as desired.
      import Math::Random::MT::Auto;
  };

=head2 Creating Subclasses

In order to create a subclass of this module, you must implement your
constructor along these lines:

  use Math::Random::MT::Auto;
  our @ISA = qw(Math::Random::MT::AUto);

  # Create a new object
  sub new
  {
      my $thing = shift;
      my $class = ref($thing) || $thing;

      my $self = {};
      bless($self, $class)

      if (! $self->_init($thing, @_)) {
          # Failed to initialize
          # Throw some sort of error, or
          return;   # Returns 'undef'
      }

      return ($self);
  }

And you need an initialization routine that provides for proper use of the
parent class's intialization routine:

  # Initialize a new object
  sub _init
  {
      my $self  = shift;
      my $thing = shift;

      # Separate '@_' into args for parent class and args for this subclass
      my @parent_args = ...;
      my @my_args     = ...;

      # Perform parent class initialization
      if (! $self->SUPER::_init($thing, @parent_args)) {
          # Parent class initialization failed
          return (0);
      }

      # Perform subclass initialization
      # Making use of '@my_args', if any
      if (ref($thing)) {
          # $thing->new( ... ) was called
          # Make use of '@my_args', if any
          # And make use of object's data, if applicable

      } else {
          # CLASS->new( ... ) was called
          # Make use of '@my_args', if any
      }

      return (1);
  }

=head1 EXAMPLES

=item Cloning the standalone PRNG to an object

=over

  use Math::Random::MT::Auto qw/rand irand state/;

  my $prng = Math::Random::MT::Auto->new('STATE' => state());

The standalone PRNG and the PRNG object will now return the same sequence
of pseudo-random numbers.

=back

=item Save state to file

=over

  use Data::Dumper;
  use Math::Random::MT::Auto qw/rand irand state/;

  my $state = state();
  if (open(my $FH, '>/tmp/rand_state_data.tmp')) {
      print($FH Data::Dumper->Dump([$state], ['state']));
      print($FH "1;\n");
      close($FH);
  }

=back

=item Use state as stored above

=over

  use Math::Random::MT::Auto qw/rand irand state/;

  our $state;
  my $rc = do('/tmp/rand_state_data.tmp');
  unlink('/tmp/rand_state_data.tmp');
  if ($rc) {
      state($state);
  }

=back

=head1 DIAGNOSTICS

This module sets a 10 second timeout for Internet connections so that if
something goes awry when trying to get seed data from an Internet source,
your application will not hang for an inordinate amount of time.

If you connect to the Internet through an HTTP proxy, then you must set the
C<http_proxy> variable in your environment when using the Internet seed
sources.  (See L<LWP::UserAgent/"Proxy attributes">.)

The HotBits site has a quota on the amount of data you can request in a
24-hour period.  (I don't know how big the quota is.)  Therefore, this
source may fail to provide any data if used too often.

If the module cannot acquire any seed data from the specified sources, then
the time() and PID will be used to seed the PRNG.  Use L</"warnings"> to
check for seed acquisition problems.

It is possible to seed the PRNG with more than 19968 bits of data (through
the use of a seeding subroutine supplied to L</"srand">, or by supplying a
large array ref of data to L</"seed">).  However, doing so does not make
the PRNG "more random" as 19968 bits more than covers all the possible PRNG
state vectors.

=head1 PERFORMANCE

Under Windows, this module is 2.5 times faster than Math::Random::MT for
the functional interface to the standalone PRNG, and 2 times faster for the
OO interface.  Under Solaris, it's 4x and 3.5x faster, respectively.  The
file F<samples/random>, included in this module's distribution, can be used
to compare timing results.

Depending on your connnection speed, acquiring seed data from the Internet
may take up to couple of seconds.  This delay might be apparent when your
application is first started, or after creating a new PRNG object.  This is
especially true if you specify the C<hotbits> source twice (so as to get
the full seed from the HotBits site) as this results in two accesses to the
Internet.  (If F</dev/urandom> is available on your machine, then you
should definitely consider using the Internet sources only as a secondary
source.)

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

Gaussian distribution function code:
L<http://home.online.no/~pjacklam/notes/invnorm/>

Creating subclasses:
L<perlobj> and L<http://www.perlmonks.org/?node_id=8177>

L<LWP::UserAgent>

L<Math::Random::MT>

L<Net::Random>

=head1 AUTHOR

Jerry D. Hedden, S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

=head1 COPYRIGHT AND LICENSE

- Mersenne Twister PRNG -

A C-Program for MT19937 (32- and 64-bit versions), with initialization
improved 2002/1/26.  Coded by Takuji Nishimura and Makoto Matsumoto,
and including Shawn Cokus's optimizations.

 Copyright (C) 1997 - 2004, Makoto Matsumoto and Takuji Nishimura,
  All rights reserved.
 Copyright (C) 2005, Mutsuo Saito, All rights reserved.
 Copyright 2005 Jerry D. Hedden S<E<lt>jdhedden AT 1979 DOT usna DOT comE<gt>>

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
 S<E<lt>m-mat AT math DOT sci DOT hiroshima-u DOT ac DOT jpE<gt>>
 L<http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>

- Gaussian Function Code -

 Author: Peter J. Acklam
 http://home.online.no/~pjacklam/notes/invnorm/
 C implementation by V. Natarajan
 Released to public domain

=cut
