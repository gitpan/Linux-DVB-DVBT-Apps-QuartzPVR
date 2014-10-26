package Linux::DVB::DVBT::Apps::QuartzPVR::Config::Constants ;

=head1 NAME

Config::Constants - Constants

=head1 SYNOPSIS

use Linux::DVB::DVBT::Apps::QuartzPVR::Config::Constants ;

=head1 DESCRIPTION

Constants for the QuartzPVR app.

=head1 AUTHOR

Steve Price 

=head1 BUGS

None that I know of!

=head1 INTERFACE


=cut


use strict ;

## Version ##################################################################
our $VERSION = '1.001' ;

## Use ######################################################################
use Carp ;
use File::Basename ;

use Linux::DVB::DVBT::Apps::QuartzPVR::Config::PHP ;

## Class Variables ##########################################################
my $debug = 0 ;

# Constant
my @FIELD_LIST = qw// ;
my @REQ_LIST = qw// ;

# Constants - note: paths get updated at initialisation
my %constants = (

) ;



## Constructor ##############################################################

=over 4

=item C<Constants::Config-E<gt>new()>

Return a reference to a new Constants::Config object. This is not necessary because all constants
can be accessed using the class name.

=cut

# MUST specify: NOTHING
sub new
{
	my ($obj, %args) = @_ ;

	my $class = ref($obj) || $obj ;

	# Create object
	my $self = {} ;
	bless ($self, $class) ;

	# Initialise object
	$self->_init(%args) ;

	# Check for required settings
	foreach (@REQ_LIST)
	{
		do 
		{ 
			croak "ERROR: $class : Must specify setting for $_" ; 
		} unless defined($self->{$_}) ;
	}

	return($self) ;
}

## Init #####################################################################
sub _init
{
	my $self = shift ;
	my (%args) = @_ ;

	# Defaults
	$self->{$_} = undef foreach(@FIELD_LIST) ;

	# Set fields from parameters
	$self->set(%args) ;

}


## Destroy ##################################################################

sub DESTROY
{
	my $self = shift ;

	print "Config::Constants->DESTROY($self)\n" if $self->debug ;

	undef $self ;
}



## Class Methods ############################################################

#----------------------------------------------------------------------------
# Debug
sub debug
{
	my $class = shift ;
	my $flag = shift ;

	my $old = $debug ;
	$debug = $flag if defined($flag) ;

	return $old ;
}



## Object Data Methods ######################################################

#----------------------------------------------------------------------------
# Set a parameter
#
sub set
{
	my $self = shift ;
	my (%args) = @_ ;

	# Args
	foreach my $field (@FIELD_LIST)
	{
		if (exists($args{$field})) 
		{
			$self->$field($args{$field}) ;
		}
	}
}


## Object Methods ###########################################################

=item C<Constants::Config-E<gt>get(I<name>)>

Return a the value of the constant I<name>, or B<undef> if no constant of that name is found.

The following constants are defined:

=cut

#---------------------------------------------------------------------
# Get the constant
#
sub get 
{
	my $self = shift ;
	my ($key) = @_ ;

	my $value = undef ;

	$value = $constants{lc $key} if exists $constants{lc $key} ;

	return $value ;
}


## Private Methods ###########################################################

#---------------------------------------------------------------------
sub _load_module
{
	my ($mod) = @_ ;
	
	my $ok = 1 ;

	# see if we can load up the package
	if (eval "require $mod") 
	{
		$mod->import() ;
	}
	else 
	{
		# Can't load package
		$ok = 0 ;
	}
	return $ok ;
}



#---------------------------------------------------------------------
# Class init - load in the constants from the PHP module
#
{

##$Linux::DVB::DVBT::Apps::QuartzPVR::Config::PHP::DEBUG=1;

	# Note: Loads vars into this namespace
	require_php("Config::Constants", "Linux::DVB::DVBT::Apps::QuartzPVR::Config::Constants") ;

	## Set up SQL	
	my $const = "package Linux::DVB::DVBT::Apps::QuartzPVR::Config::Constants ;\n" ;
	if (_load_module("Linux::DVB::DVBT::Apps::QuartzPVR::Config::SqlConstants"))
	{
		$const .= "use constant 'SQL_USER' => '$Linux::DVB::DVBT::Apps::QuartzPVR::Config::SqlConstants::SQL_USER'; \n" ;
		$const .= "use constant 'SQL_PASSWORD' => '$Linux::DVB::DVBT::Apps::QuartzPVR::Config::SqlConstants::SQL_PASSWORD';\n" ;
	}
	else
	{
		$const .= "use constant 'SQL_USER' => ''; \n" ;
		$const .= "use constant 'SQL_PASSWORD' => '';\n" ;
	}

##print "EVAL: $const\n" ;	
	eval $const ;
	if ($@)
	{
		print $@ ;
	}
	

	## Defaults - put contants into environment (with DEF_ prefix so prog options can use the variables as defaults)
	foreach my $var (qw/PVR_ROOT PVR_HOME SERVER_PORT PVR_USER PVR_GROUP PVR_LOGDIR 
		DVBT_FREQFILE MAIL_TO
		DATABASE VIDEO_DIR AUDIO_DIR
		RECPROG IPLAYPROG SCRIPTS_DIR
		TBL_LISTINGS TBL_RECORD TBL_CHANNELS TBL_RECORDING TBL_RECORDED TBL_SCHEDULE TBL_MULTIREC TBL_IPLAY/)
	{
		my $cvar = 'Linux::DVB::DVBT::Apps::QuartzPVR::Config::Constants::' . $var ;
		my $val ;
		eval "\$val = $cvar" ;
		$ENV{"DEF_$var"} = $val ;
	}

}


## DEBUG ###########################################################



1;


