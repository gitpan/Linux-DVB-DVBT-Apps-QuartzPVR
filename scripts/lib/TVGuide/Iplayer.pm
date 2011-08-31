package TVGuide::Iplayer ;

=head1 NAME

TVGuide::Iplayer - Manage get_iplayer recording scheduling

=head1 SYNOPSIS

use TVGuide::Iplayer ;


=head1 DESCRIPTION


=head1 DIAGNOSTICS

Setting the debug flag to level 1 prints out (to STDOUT) some debug messages, setting it to level 2 prints out more verbose messages.

=head1 AUTHOR

Steve Price 

=head1 BUGS

None that I know of!

=head1 INTERFACE

=over 4

=cut

use strict ;
use Carp ;

our $VERSION = "1.001" ;

#============================================================================================
# USES
#============================================================================================
use TVGuide::Base::Object ;
use TVGuide::Prog ;
use TVGuide::Crontab ;

#============================================================================================
# OBJECT HIERARCHY
#============================================================================================
our @ISA = qw(TVGuide::Base::Object) ; 

#============================================================================================
# GLOBALS
#============================================================================================

## Iplayer HASH entry eventually contains:
#
# From SQL:
#	pid 
#	channel 
#	title 
#	date   (YYYY/MM/DD for Date::Manip)
#	start 
#	duration 
#	episode 
#	num_episodes 
#	repeat 
#	chan_type 
#	record
#
# Created:
#  end	= end time
#  duration_secs = duration time in seconds
#  start_datetime = Date::Manip date for start time/date
#  end_datetime = Date::Manip date for start time/date
#  start_dt_mins = minutes from 1970 for start date/time
#  end_dt_mins = minutes from 1970 for end date/time
#
#


my %FIELDS = (
	'phase'			=> '',
	'iplay_time'	=> '01:00',
	

	## Internal
	'_tvsql'		=> undef,		# TVGuide::Sql object
	'_tvrec'		=> undef,		# TVGuide::Recording object
	'_tvreport'		=> undef,		# TVGuide::Report object
) ;


#============================================================================================
# CONSTRUCTOR 
#============================================================================================

=item C<new([%args])>

Create a new object.

The %args are specified as they would be in the B<set> method, for example:

	'mmap_handler' => $mmap_handler

The full list of possible arguments are :

	'fields'	=> Either ARRAY list of valid field names, or HASH of field names with default values 

=cut

sub new
{
	my ($obj, %args) = @_ ;

	my $class = ref($obj) || $obj ;

	# Create object
	my $this = $class->SUPER::new(%args) ;

	return($this) ;
}



#============================================================================================
# CLASS METHODS 
#============================================================================================

#-----------------------------------------------------------------------------

=item C<init_class([%args])>

Initialises the Cwrsync object class variables. Creates a class instance so that these
methods can also be called via the class (don't need a specific instance)

=cut

sub init_class
{
	my $class = shift ;
	my (%args) = @_ ;

	if (! keys %args)
	{
		%args = () ;
	}
	
	# Add extra fields
	$class->add_fields(\%FIELDS, \%args) ;

	# init class
	$class->SUPER::init_class(%args) ;

	# Create a class instance object - allows these methods to be called via class
	$class->class_instance(%args) ;
	
}

#============================================================================================
# OBJECT DATA METHODS 
#============================================================================================



#============================================================================================
# OBJECT METHODS 
#============================================================================================

#---------------------------------------------------------------------
# Read the existing SQL table and convert to the list of real recordings
# May well include duplicates
#
sub existing_schedule
{
	my $this = shift ;
	my $tvsql = $this->_tvsql ;
	my $tvrec = $this->_tvrec ;
	
	my @iplay = $tvsql->select_iplay() ;

	$this->fix_times(\@iplay) ;	
	
	# Set up sub-title entry
	foreach (@iplay)
	{
		$_->{'subtitle'} ||= Linux::DVB::DVBT::Utils::subtitle($_->{'text'}) ;
	}
	
	# Set correct start time/date
	my @schedule ;
#	foreach my $prog_href (sort { TVGuide::Prog::start_cmp($a, $b) } @iplay)
#	{
#		## Calc date of recording
#		my $entry_href = $this->_schedule_recording($prog_href) ;
#		push @schedule, $entry_href ;
#	}
	
@schedule = sort { TVGuide::Prog::start_cmp($a, $b) } @iplay ;	

	return @schedule ;
}

#---------------------------------------------------------------------
# Gets the latest scheduled recordings list from the database and also
# sets up various date/time values for later use
sub fix_times
{
	my $this = shift ;
	my ($schedule_aref) = @_ ;

	# Set up times
	foreach (@$schedule_aref)
	{
		# Set end time etc
		# only do so if extra information hasn't already been set
		unless (exists($_->{'start_dt_mins'}))
		{
			TVGuide::Prog::set_times($_) ;
		}
	}
}


#---------------------------------------------------------------------
# Schedule each program for the following day at the specified time
#
sub schedule_recordings
{
	my $this = shift ;
	my ($recording_schedule_aref, $schedule_aref) = @_ ;

print "Iplayer::schedule_recordings()\n" if $this->debug >= 4 ;

	TVGuide::Base::DbgProf::startfn() ;

	my $tvreport = $this->_tvreport ;

	## filter out any recordings that include DVBT (they get handled elsewhere)
	my @iplay_only_recordings = $this->filter_iplay($recording_schedule_aref) ;

	# report
	$tvreport->recordings(\@iplay_only_recordings) ;
	$this->_new_phase('initial IPLAY') ;
	$tvreport->scheduling($schedule_aref, []) ;

TVGuide::Prog::disp_sched("Iplayer::P0 Recordings=", $recording_schedule_aref) if $this->debug >= 4 ;
TVGuide::Prog::disp_sched("Iplayer::P0 Schedule=", $schedule_aref) if $this->debug >= 4 ;

	foreach my $prog_href (@iplay_only_recordings)
	{
		TVGuide::Base::DbgTrace::add_rec($prog_href, {
			'seen'	=> 1,	
		}) ;
		
		
		## Calc date of recording
		my $entry_href = $this->_schedule_recording($prog_href) ;
		
		push @{$schedule_aref}, $entry_href ;

		TVGuide::Base::DbgTrace::add_rec($entry_href, "scheduled for IPLAY") ;
	}

	TVGuide::Base::DbgProf::waypoint("IPLAY processed recordings") ;

	TVGuide::Prog::disp_sched("IPLAY Final schedule:", $schedule_aref) if ($this->debug) ;

	# Report
	$this->_new_phase('final IPLAY') ;
	$tvreport->scheduling($schedule_aref, []) ;

	TVGuide::Base::DbgProf::endfn() ;
}

#---------------------------------------------------------------------
# Schedule a single IPLAY program for the following day at the specified time
#
sub _schedule_recording
{
	my $this = shift ;
	my ($prog_href) = @_ ;

print "Iplayer::_schedule_recording()\n" if $this->debug >= 4 ;

	TVGuide::Base::DbgProf::startfn() ;

	## Calc date of recording
	
	# 
	#  | day           | day+1          | day+2         |
	#        ^----^                                 ^
	#             |------+2days---------------------|
	#                                     :<--------|
	#    :               :                :                :
	#                                    use this 
	#                                    get_iplay
	#                                    download slot
	#
	#
	my $end_dt = $prog_href->{'end_datetime'} ;
	$end_dt = TVGuide::Time::dt_offset($end_dt, "+ 1 day") ;
	
	my $entry_href = {%$prog_href} ;
	$entry_href->{'date'} = TVGuide::Time::dt2date($end_dt) ;
	$entry_href->{'start'} = $this->iplay_time ;
	
	TVGuide::Prog::set_times($entry_href) ;
	
	$entry_href->{'prog_date'} = $prog_href->{'date'} ;
	$entry_href->{'prog_start'} = $prog_href->{'start'} ;

	TVGuide::Base::DbgProf::endfn() ;

	return $entry_href ;
}



#---------------------------------------------------------------------
# Update cron jobs
#
sub update_cron
{
	my $this = shift ;
	my ($schedule_aref) = @_ ;

	TVGuide::Base::DbgTrace::startfn('update cron') ;
	TVGuide::Base::DbgProf::startfn() ;

	## Set cron
	TVGuide::Crontab::update_iplay($schedule_aref) ;

	TVGuide::Base::DbgProf::endfn() ;

}

#---------------------------------------------------------------------
# Commit the final schedule (both to database and cron jobs)
#
sub commit
{
	my $this = shift ;
	my ($schedule_aref, $test) = @_ ;

	TVGuide::Base::DbgTrace::startfn('commit') ;
	TVGuide::Base::DbgProf::startfn() ;

	## Set database
	my $tvsql = $this->_tvsql ;
	unless ($test>=2)
	{
		## Enter sorted by record id RID
		my @sorted = sort { $a->{'rid'} <=> $b->{'rid'} } @$schedule_aref ;
		$tvsql->update_iplay_table(\@sorted) ;
	}

	TVGuide::Base::DbgProf::endfn() ;
}

#---------------------------------------------------------------------
# Remove any recordings matching this RID
# 
#
sub unschedule
{
	my $this = shift ;
	my ($schedule_aref, $rid) = @_ ;

	my @sched = (@$schedule_aref) ;
	@$schedule_aref = () ;
	
	foreach my $href (@sched)
	{
		if ($href->{'rid'} != $rid)
		{
			push @$schedule_aref, $href ;
		}
	}
}


#---------------------------------------------------------------------
# Replace all rids set to NEW_RID with the specified new value
#
sub update_rid($new_rid, \@schedule)
{
	my $this = shift ;
	my ($new_rid, $schedule_aref) = @_ ;
	
	foreach my $href (@$schedule_aref)
	{
		my @progs = ($href) ;
		foreach my $rec_href (@progs)
		{
			if ($rec_href->{'rid'} == $TVGuide::Base::Constants::NEW_RID)
			{
				$rec_href->{'rid'} = $new_rid ;
			}
		}
	}
}


#---------------------------------------------------------------------
# Start a new scheduling phase
sub _new_phase
{
	my $this = shift ;
	my ($phase) = @_ ;

	## save phase for tracing
	$this->phase($phase) ;
	
	## set report
	my $tvreport = $this->_tvreport ;
	$tvreport->new_phase($phase) ;
}


#---------------------------------------------------------------------
# filter out any recordings that include DVBT (they get handled elsewhere)
#
sub filter_iplay
{
	my $this = shift ;
	my ($recording_schedule_aref) = @_ ;

	my @iplay_only_recordings = () ;
	foreach my $prog_href (@$recording_schedule_aref)
	{
		if ($prog_href->{'type'} eq 'multiplex')
		{
			my @progs = @{$prog_href->{'multiplex'}} ;
			@{$prog_href->{'multiplex'}} = () ;
			foreach my $href (@progs)
			{
				if (TVGuide::Base::Constants::has_iplay($href->{'record'}))
				{
					# skip anything that doesn't have IPLAY
					push @{$prog_href->{'multiplex'}}, $href ;
				}
			}
			
			# save multiplex if multiplex actually contains something
			if (@{$prog_href->{'multiplex'}})
			{
				push @iplay_only_recordings, $prog_href ;
			}
		}
		else
		{
			if (TVGuide::Base::Constants::has_iplay($prog_href->{'record'}))
			{
				# skip anything that doesn't have IPLAY
				push @iplay_only_recordings, $prog_href ;
			}
		}

	}
	return @iplay_only_recordings ;
}



#============================================================================================
# DEBUG
#============================================================================================
#



# ============================================================================================
# END OF PACKAGE
1;

__END__


