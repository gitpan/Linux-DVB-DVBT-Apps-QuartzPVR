package TVGuide ;

=head1 TODO

* php interface to talk to web page
** status update %
** pausing due to cron job about to start

* recording - allow multiple of same prog, but with different priorities. Override lowest priority with higher. (e.g. background Midsomer Murders + high priority for new episodes)

* blob/list object

* multiplex recording

* In report: make a COPY of hash entry to show contents at that time

* Logfile option: use this to write direct to logfile (rather than stdout)

* test suite: set up test sql and run a suite of tests to check results (Test::More?)


* fix: tried recording all"flash forward" just recorded 1 prog?



=head1 NAME

TVGuide - Wrapper for TVGuide recording scheduler

=head1 SYNOPSIS

use TVGuide::Schedule ;


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

our $VERSION = "1.008" ;

#============================================================================================
# USES
#============================================================================================
use Linux::DVB::DVBT ;

use TVGuide::Base::Object ;

use TVGuide::Base::Constants ;
use TVGuide::Base::DbgTrace ;
use TVGuide::Base::DbgProf ;
use TVGuide::Series ;
use TVGuide::Recording ;
use TVGuide::Report ;
use TVGuide::Schedule ;
use TVGuide::Iplayer ;
use TVGuide::Prog ;
use TVGuide::Sql ;
use TVGuide::Crontab ;
use TVGuide::Mail ;

#============================================================================================
# OBJECT HIERARCHY
#============================================================================================
our @ISA = qw(TVGuide::Base::Object) ; 

# TODO: Create HTML report page (optional) - include date/time in filename

# TODO: Re-schedule based on chan+1 ?
# TODO: Re-schedule based on prog repeat (same title+description etc?)

# TODO: Series link
# TODO: Series - record to title dir / episode name


#============================================================================================
# GLOBALS
#============================================================================================

my %FIELDS = (

	## User specified settings
	'date'			=> 'today',		# start date
	'trace_flag'	=> 0,			# set to print out trace
	'profile_flag'	=> 0,			# set to print out profile
	'test'			=> 0,			# test mode - don't do final schedule commit
	
	'enable_multirec'	=> 0,		# allow multiplex recording
	'max_timeslip'		=> 0,		# 
	'run_dir'			=> '/var/log/users/sdprice1/dvb_record_mgr',
	'log_dir'			=> '/var/log/users/sdprice1',
	'run_ext'			=> '.lst',

	'video_dir'			=> undef,		# video recording dir
	'audio_dir'			=> undef,		# audio recording dir
	'video_path'		=> undef,		# video recording path spec
	'audio_path'		=> undef,		# audio recording path spec
	'variables'			=> undef,
	
	'padding'		=> undef,
	'margin'		=> 1,			# number of hours for fuzzy prog search
	'early'			=> undef,
	'date'			=> undef,
	'log'			=> undef,
	'report'		=> undef,
	'php'			=> undef,
	
	'recprog'		=> undef,
	'iplayprog'		=> undef,
	'iplay_time'	=> undef,

	## Sql - user specified
	'sql'			=> undef,		# set to Database handler object
	
	'database'		=> undef,		# Database name
	'tbl_recording'	=> undef,		# database table for recordings requests
	'tbl_listings'	=> undef,		# database table for tvguide listings
	'tbl_schedule'	=> undef,		# database table for resulting scheduled recordings
	'tbl_multirec'	=> undef,		# database table for multiplex recordings
	'tbl_iplay'		=> undef,		# database table for get_iplayer scheduled recordings
	'tbl_chans'		=> undef,		# database table for list of channels
	'tbl_recorded'	=> undef,		# database table for recorded programs
	
	'user'			=> '',
	'password'		=> '',
	
	## DVB
	'devices'		=> [],
	'num_adapters'	=> 0,
	
	## Internal
	'_tvsql'		=> undef,		# TVGuide::Sql object
	'_tvrec'		=> undef,		# TVGuide::Recording object
	'_tvreport'		=> undef,		# TVGuide::Report object
	'_tvsched'		=> undef,		# TVGuide::Schedule object
	'_tviplay'		=> undef,		# TVGuide::Iplayer object
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
	
	TVGuide::Base::DbgTrace::trace_flag($this->trace_flag) ;
	TVGuide::Base::DbgProf::profile_flag($this->profile_flag) ;
	
	## Variables
	my $vars_href = $this->variables() || {} ;
	my %vars = (
#		%ENV,
		%$vars_href,
	) ;

	## TVGuide::Sql object
	my $tvsql = TVGuide::Sql->new(
		'app'			=> $this->app,
		'sql'			=> $this->sql,		
		'database'		=> $this->database,
		'tbl_recording'	=> $this->tbl_recording,
		'tbl_listings'	=> $this->tbl_listings,	
		'tbl_schedule'	=> $this->tbl_schedule,
		'tbl_multirec'	=> $this->tbl_multirec,
		'tbl_iplay'		=> $this->tbl_iplay,
		'tbl_chans'		=> $this->tbl_chans,
		'tbl_recorded'	=> $this->tbl_recorded,
		
		'rec_dvbt_iplay'=> $TVGuide::Base::Constants::REC_GROUPS{'DVBT_IPLAY'},
		'rec_iplay'		=> $TVGuide::Base::Constants::REC_GROUPS{'IPLAY'},
		
		'user'			=> $this->user,
		'password'		=> $this->password,
		
		'debug'			=> $args{'dbg_sql'},
	) ;
	$tvsql->init_sql() ;

	## TVGuide::Recording object
	my $tvrec = TVGuide::Recording->new(
		'app'		=> $this->app,
		'tvsql'		=> $tvsql,
		'margin'	=> $this->margin,
		'debug'		=> $args{'dbg_recording'},
	) ;

	## TVGuide::Report object
	my $tvreport = TVGuide::Report->new(
		'app'		=> $this->app,
		'debug'		=> $args{'dbg_report'},
	) ;

	## TVGuide::Schedule object
	my $tvsched = TVGuide::Schedule->new(
		'app'		=> $this->app,
		'debug'		=> $args{'dbg_schedule'},
	) ;

	## TVGuide::Iplayer object
	my $tviplay = TVGuide::Iplayer->new(
		'app'			=> $this->app,
		'iplay_time'	=> $this->iplay_time,
		'debug'			=> $args{'dbg_iplay'},
	) ;

	## save objects
	$this->set(
		'_tvsql'		=> $tvsql,	
		'_tvrec'		=> $tvrec,	
		'_tvreport'		=> $tvreport,
		'_tvsched'		=> $tvsched,
		'_tviplay'		=> $tviplay,
	) ;
	$tvsched->set(
		'_tvsql'		=> $tvsql,	
		'_tvrec'		=> $tvrec,	
		'_tvreport'		=> $tvreport,
	) ;
	$tviplay->set(
		'_tvsql'		=> $tvsql,	
		'_tvrec'		=> $tvrec,	
		'_tvreport'		=> $tvreport,
	) ;

	## Get number of available DVB adapters
  	my @devices = Linux::DVB::DVBT->device_list() ;
	my $total_num_adapters = @devices ;
	my $num_adapters = $args{'num_adapters'} || $total_num_adapters ;
	$num_adapters = $total_num_adapters if ($num_adapters > $total_num_adapters) ;
	
	die "ERror: You must have at least one DVB-T adapter available for recording" unless $num_adapters ;
	
	$this->set(
		'devices'		=> \@devices,
		'num_adapters'	=> $num_adapters,
	) ;
	
	# report
	$tvreport->devices(\@devices) ;

	## Init cron
	TVGuide::Crontab::set(
		'app'			=> $this->app,

		'padding'		=> $this->padding,
		'early'			=> $this->early,
		'recprog'		=> $this->recprog,
		'iplayprog'		=> $this->iplayprog,
		'video_dir'			=> $this->video_dir,
		'audio_dir'			=> $this->audio_dir,
		'log'			=> $this->log,
		'crontag'		=> 'dvb-record',
		'debug'			=> $args{'dbg_cron'},
		
		'log_dir'		=> $this->log_dir,
		'run_dir'		=> $this->run_dir,
		'run_ext'		=> $this->run_ext,
		'max_timeslip'	=> $this->max_timeslip,		# max timeslip time in minutes ; 0 = no timeslip
	) ;

	## Init Series
	TVGuide::Series::set(
		'app'				=> $this->app,
		'video_dir'			=> $this->video_dir,
		'audio_dir'			=> $this->audio_dir,
		'video_path'		=> $this->video_path,
		'audio_path'		=> $this->audio_path,
		'variables'			=> \%vars,

		'debug'			=> $args{'dbg_series'},
	) ;

	## Init mail
	TVGuide::Mail::set(
		'tvreport'	=> $tvreport,
		'debug'		=> $args{'dbg_mail'},
	) ;
	
	## debug
	$TVGuide::Prog::debug = $args{'dbg_prog'} ;
	$TVGuide::Base::DbgTrace::debug = $args{'dbg_dbg_trace'} ;

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

#--------------------------------------------------------------------------------------------
# Works out what to do based on the command options, then does it
sub process
{
	my $this = shift ;
	my ($opts_href) = @_ ;
	
	if ($opts_href->{'info'})
	{
		## Display settings
		$this->show_info($opts_href) ;
	}
	elsif ($opts_href->{'rec'})
	{
		## Handle new/changed recording 
		$this->modify_recording($opts_href->{'rec'}) ;
	}
	else
	{
		## Do the update
		$this->update() ;
	}
	
}

#--------------------------------------------------------------------------------------------
# Gathers all the latest information from the EPG database and the recordings database and re-schedules
sub update
{
	my $this = shift ;

	TVGuide::Base::DbgProf::startfn() ;
	TVGuide::Base::DbgTrace::trace_clear() ;

print "TVGuide::update() : ".$this->date."\n" if $this->debug ;
	
	my $tvrec = $this->_tvrec ;
	my $tvreport = $this->_tvreport ;
	my $tvsched = $this->_tvsched ;
	my $tviplay = $this->_tviplay ;
	my $num_adapters = $this->num_adapters ;


	## Get list of recordings and expand into schedule (ignoring any old programs) 
	my @schedule = () ;
	my @iplay_schedule = () ;
	my @unscheduled = () ;
	my @recording_schedule = $tvrec->get_recording($this->date) ;
	my @iplay_recordings = $tvrec->get_iplay_recording($this->date) ;

TVGuide::Prog::disp_sched("IPLAY recordings=", \@iplay_recordings) if $tviplay->debug >= 4 ;
TVGuide::Prog::disp_sched("DVBT recordings=", \@recording_schedule) if $tvsched->debug >= 4 ;

	
	## Ensure any current recordings are marked as "locked"
	my @existing_schedule = $tvsched->existing_schedule() ;
	$tvsched->mark_locked_recordings(\@recording_schedule, \@existing_schedule) ;
	
	## Handle any get_iplayer recordings
	$tviplay->schedule_recordings(\@iplay_recordings, \@iplay_schedule) ;

	## Perform the scheduling (of DVBT recordings)
	my $ok = $tvsched->schedule_recordings($num_adapters, \@recording_schedule, \@schedule, \@unscheduled, 
		'enable_multirec' 	=> $this->enable_multirec,
		'max_timeslip' 		=> $this->max_timeslip,
	) ;

TVGuide::Prog::disp_sched("IPLAY schedule=", \@iplay_schedule) if $tviplay->debug >= 4 ;
TVGuide::Prog::disp_sched("DVBT schedule=", \@schedule) if $tvsched->debug >= 4 ;

	
	## If unscheduled programs
	if (!$ok && !$this->test)
	{
		## Mail warning
		TVGuide::Mail::mail_error("dvb_record_mgr unscheduled", "Warning: some programs left unscheduled during update") ;
	}

	## Update schedule
	$tvsched->update_cron(\@schedule) ;
	$tviplay->update_cron(\@iplay_schedule) ;
	$tvsched->commit(\@schedule, $this->test) ;
	$tviplay->commit(\@iplay_schedule, $this->test) ;

	## Print report if required
	if ($this->report)
	{
		## Create report
		$tvreport->print_report() ;
	
		# check cron
		TVGuide::Crontab::check_cron() ;
	}

	## Output to PHP if required
	if ($this->php)
	{
		if (!$ok)
		{
			## Report warning
			$this->php_unscheduled(\@unscheduled) ;
		}		
	}

	TVGuide::Base::DbgProf::endfn() ;

	return $ok ;
}

#--------------------------------------------------------------------------------------------
# Uses the existing schedule, but adds/modifies the specified recording(s)
#
#Expect a record specification of one of the following two forms. First form creates a new recording:
#
#  'rec:<level>:pid:<program id>:'
#
#Second form modifies (or deletes if level=0) an existing recording:
#
#  'rec:<level>:rid:<record id>:'
#
# Mainly intended for PHP use
#
sub modify_recording
{
	my $this = shift ;
	my ($rec_spec) = @_ ;

	TVGuide::Base::DbgProf::startfn() ;
	TVGuide::Base::DbgTrace::trace_clear() ;

print "TVGuide::modify_recording() : ".$this->date."\n" if $this->debug ;

	my $ok = 0 ;
	
	my $tvsql = $this->_tvsql ;
	my $tvrec = $this->_tvrec ;
	my $tvreport = $this->_tvreport ;
	my $tvsched = $this->_tvsched ;
	my $tviplay = $this->_tviplay ;
	my $num_adapters = $this->num_adapters ;

	$tvreport->recspec($rec_spec) ;

	## Get currently scheduled recordings
	my @schedule = $tvsched->existing_schedule() ;
	my @iplay_schedule = $tviplay->existing_schedule() ;
	my @unscheduled = () ;
	my @recording_schedule = () ;
	my @requested_recording = () ;

print "Modify rec : $rec_spec\n" if $this->debug ;
TVGuide::Prog::disp_sched("Existing IPLAY schedule=", \@iplay_schedule) if $tviplay->debug >= 4 ;
TVGuide::Prog::disp_sched("Existing DVBT schedule=", \@schedule) if $tvsched->debug >= 4 ;

	## Parse spec
	## NOTE: recspec_href is NOT a full program HASH - just the recording specifics 
	my $recspec_href = $tvrec->parse_recspec($rec_spec) ;
	my $record = $recspec_href->{'rec'} ;
	
	if ($record)
	{
		## Modify/Create

		# expand rid/pid into new recordings
		my $recspec_rec_href = {} ;
		@recording_schedule = $tvrec->get_recording_from_spec($recspec_href, \$recspec_rec_href, $this->date) ;
		@requested_recording = @recording_schedule ;

if ($this->debug)
{
$this->prt_data("expanded recspec=", $recspec_rec_href) ;
TVGuide::Prog::disp_sched("spec recordings=", \@recording_schedule) ;
print "\n-=-=-=-=-=-=-=-=-=-=-=-=-=\n" ;
	if ($this->debug >= 2)
	{
	$this->prt_data("Existing schedule=", \@schedule) ;
	print "\n-=-=-=-=-=-=-=-=-=-=-=-=-=\n" ;
	}
}

		# if RID, remove existing from schedule
		if ($recspec_rec_href->{'rid'} > 0)
		{
			$tvsched->unschedule(\@schedule, $recspec_href->{'rid'}) ;
			$tviplay->unschedule(\@iplay_schedule, $recspec_href->{'rid'}) ;
$this->prt_data("removed $recspec_href->{'rid'} from schedule=", \@schedule) if $this->debug ;
$this->prt_data("removed $recspec_href->{'rid'} from IPLAY schedule=", \@iplay_schedule) if $this->debug ;
		}

print "schedule recordings...\n" if $this->debug ;

		## Handle any get_iplayer recordings
		@recording_schedule = @requested_recording ;
		$tviplay->schedule_recordings(\@recording_schedule, \@iplay_schedule) ;

		# attempt to schedule
		@recording_schedule = @requested_recording ;
		$ok = $tvsched->schedule_recordings($num_adapters, \@recording_schedule, \@schedule, \@unscheduled, 
			'enable_multirec' 	=> $this->enable_multirec,
			'max_timeslip' 		=> $this->max_timeslip,
		) ;

print "schedule recordings: ok=$ok\n" if $this->debug ;
		
		# Update database
		if ($ok)
		{
			my $rid = $recspec_rec_href->{'rid'} ;

print "$rid == $TVGuide::Base::Constants::NEW_RID\n" if $this->debug ;

			# New or modified
			if ($rid == $TVGuide::Base::Constants::NEW_RID)
			{
$this->prt_data("INSERT NEW RECORDING recspec=", $recspec_rec_href) if $this->debug ;
				# insert into database
				my $new_rid = $tvsql->insert_recording($recspec_rec_href) ;

print " + New RID = $new_rid\n" if $this->debug ;

				# replace NEW_RID (which is a placeholder value) with the real new RID value
				$tvsched->update_rid($new_rid, \@schedule) ;
				$tviplay->update_rid($new_rid, \@iplay_schedule) ;
			}
			else
			{
$this->prt_data("UPDATE EXISTING RECORDING recspec=", $recspec_rec_href) if $this->debug ;
				$tvsql->update_recording($recspec_rec_href) ;
			}
		}

##TODO: Check - if unscheduled priority > new priority (i.e. higher pri has been scheduled) then its ok
#if (!$ok)
#{
##	$ok = priority_check($rec_href, \@unscheduled) ;
#}

	}
	else
	{
		## Delete
		if ($recspec_href->{'rid'})
		{
print "DELETE EXISTING RECORDING\n" if $this->debug ;
			## delete this recording
			$tvsql->delete_recording($recspec_href->{'rid'}) ;

			##remove existing from schedule
			$tvsched->unschedule(\@schedule, $recspec_href->{'rid'}) ;
			$tviplay->unschedule(\@iplay_schedule, $recspec_href->{'rid'}) ;
$this->prt_data("removed $recspec_href->{'rid'} from schedule=", \@schedule) if $this->debug ;

			$ok = 1 ;
		}
	}

print "done ok=$ok...\n" if $this->debug ;

	## update cron jobs
	$tvsched->update_cron(\@schedule) ;
	$tviplay->update_cron(\@iplay_schedule) ;

	## If no unscheduled programs
	if ($ok)
	{
		## Update schedule
		$tvsched->commit(\@schedule, $this->test) ;
		$tviplay->commit(\@iplay_schedule, $this->test) ;
	}

	## Generate report if required
	if ($this->report)
	{
		## Create report
		$tvreport->print_report() ;
	
		# check cron
		TVGuide::Crontab::check_cron() ;
	}	

	## Output to PHP if required
	if ($this->php)
	{
		if (!$ok)
		{
			if (@requested_recording)
			{
				## Report unscheduled
				$this->php_unscheduled(\@requested_recording) ;
			}
			else
			{
				$this->php_message("Warning", ["Unexpected perl script error"]) ;
			}
		}		
	}


	TVGuide::Base::DbgProf::endfn() ;
	
	return $ok ;
}

#--------------------------------------------------------------------------------------------
# Display info
#
sub show_info
{
	my $this = shift ;
	my ($opts_href) = @_ ;
	
	my %info; 
	
	$info{'NUM_PVRS'} = $this->num_adapters() ;
	
	my $devices_aref = $this->devices ;
	
	
	## Output to PHP if required
	if ($this->php)
	{
		$this->php_info(\%info) ;
	}
	else
	{
		print "INFO:\n" ;
		foreach my $key (sort keys %info)
		{
			print "\t$key: $info{$key}\n" ;
		}
	}
	
}

#============================================================================================
# PHP
#============================================================================================
#



#--------------------------------------------------------------------------------------------
# Format the unscheduled list into a PHP message
#
sub php_unscheduled
{
	my $this = shift ;
	my ($unsched_aref) = @_ ;

	TVGuide::Base::DbgProf::startfn() ;

	my @msg ;
	push @msg, "Unable to schedule all programs. Unscheduled programs:" ;
	foreach my $prog_href (@$unsched_aref)
	{
		push @msg, "\t$prog_href->{chan} : $prog_href->{title}" ;	
	}
	$this->php_message("Warning", \@msg) ;

	TVGuide::Base::DbgProf::endfn() ;
}

#--------------------------------------------------------------------------------------------
# Format an array of text into a PHP message
#
# Should be of the form:
#
#	<?php
#	$msg_type = "warning" ;
#	$messages = array(
#		"line 1",
#		"another line"
#	) ;
#	?>
#
sub php_message
{
	my $this = shift ;
	my ($msg_type, $msg_aref) = @_ ;

	$msg_type ||= "info" ;

	TVGuide::Base::DbgProf::startfn() ;

	my $php = "<?php\n" ;
	$php .= "\t\$msg_type = \"$msg_type\";\n" ;
	$php .= "\t\$messages = array(\n" ;
	foreach my $text (@$msg_aref)
	{
		$php .= "\t\t\"$text\",\n" ;
	}
	$php .= "\t) ;\n" ;
	$php .= "?>\n\n" ;
	
	print $php ;

	TVGuide::Base::DbgProf::endfn() ;
}

#--------------------------------------------------------------------------------------------
# Format a HASH (consisting of key/scalar value pairs)into PHP
#
# Should be of the form:
#
#	<?php
#	$key1 = "scalar1" ;
#	...
#	?>
#
sub php_info
{
	my $this = shift ;
	my ($hash_ref) = @_ ;

	my $php = "<?php\n" ;
	foreach my $key (sort keys %$hash_ref)
	{
		$php .= "\$$key = \"$hash_ref->{$key}\";\n" ;
	}

	$php .= "?>\n\n" ;
	
	print $php ;
}




# ============================================================================================
# END OF PACKAGE
1;

__END__


