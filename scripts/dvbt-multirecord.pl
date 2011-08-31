#!/usr/bin/perl
#
# Based on Linux::DVB::DVBT example script but with added debug & error checking
#
use strict ;
use File::Path ;
use File::Basename ;
use File::Copy ;
use Pod::Usage ;
use Getopt::Long qw/:config no_ignore_case/ ;

++$! ;


## CPAN REQUIRED:
use Linux::DVB::DVBT ;
use Linux::DVB::DVBT::TS ;
use Linux::DVB::DVBT::Ffmpeg ;
use Linux::DVB::DVBT::Config ;
use Linux::DVB::DVBT::Advert ;

use MP3::Tag ;
use DBI ;
use DBD::mysql ;
## CPAN REQUIRED

our $VERSION = '4.004' ;

my @info_lines ;

	my $progname = basename $0 ;
	my $ok = 1 ;
	

	my ($help, $man, $DEBUG, $VERBOSE, $config, $adap, $DBG_FFMPEG, $DBG_SQL) ;
	my ($rootdir) = "" ;
	my ($trash) = "/served/videos/PVR/Misc/TRASH" ;
	my ($mailto) = 'quartz@quartz-net.co.uk' ;
	my ($log) = '/var/log/users/sdprice1/dvbt-multirec.log' ;
	
	my %dbh = (
		'host' 		=> 'localhost',
		'db' 		=> 'tvguide',
		'tbl' 		=> 'recorded2',
		'user' 		=> 'steve',
		'password' 	=> 'zzsqlsteve',
	) ;
	
	
	my $adskip=1 ;
	my $rec_file ;
	
	my $event ;
	my $timeslip ;
	my $sliptype ;
	my $title ;
	my $episode ;
	my $id ; 
	
	# Default to recording TS (do not transcode)
	my $force_ts = 0 ;
	
	GetOptions('v|verbose=s' => \$VERBOSE,
			   'debug=i' => \$DEBUG,
			   'dbg-ffmpeg=i' => \$DBG_FFMPEG,
			   'dbg-sql=i' => \$DBG_SQL,
			   'h|help' => \$help,
			   'man' => \$man,
			   
			   'a=s' => \$adap,
			   'root=s' => \$rootdir,
			   'trash=s' => \$trash,
			   'file=s' => \$rec_file,

			   'event=s' => \$event,
			   'timeslip=s' => \$timeslip,
			   'sliptype=s' => \$sliptype,
			   'title=s' => \$title,
			   'episode=s' => \$episode,
			   'id=s' => \$id,
			   
			   'cfg=s' => \$config,
			   'mail=s' => \$mailto,
			   'force_ts=i' => \$force_ts,
			   'adskip=i' => \$adskip,
			   
			   ) or pod2usage(2) ;

	my $dvb_name = sprintf "DVB%d", $adap ;

	## Add alternate encoder - use vlc
	unshift @{$Linux::DVB::DVBT::Ffmpeg::COMMANDS{'mpeg'}},
		'vlc -I dummy "$src" --sout "#standard{mux=ps,dst=\"$dest.$ext\",access=file}" vlc://quit' ;

	info("===============================================================") ;
	info("$progname v$VERSION") ;
	info("Linux::DVB::DVBT v$Linux::DVB::DVBT::VERSION") ;
	info("Linux::DVB::DVBT::Advert v$Linux::DVB::DVBT::Advert::VERSION") ;

    pod2usage(1) if $help;
    pod2usage(-verbose => 2) if $man;
    if (!$rec_file)
    {
	    pod2usage("$0: No arguments given.")  if (@ARGV == 0) ;
	    pod2usage("$0: No filename given.")  if (@ARGV <= 1) ;
	    pod2usage("$0: No duration given.")  if (@ARGV <= 2) ;
    }
    
	Linux::DVB::DVBT->debug($DEBUG) ;
	Linux::DVB::DVBT->dvb_debug($DEBUG) ;
	Linux::DVB::DVBT->verbose($VERBOSE) ;
	
	$Linux::DVB::DVBT::Ffmpeg::DEBUG = $DBG_FFMPEG if $DBG_FFMPEG ;
	
	
	## Create dvb (use first found adapter). 
	## NOTE: With default object settings, the application will
	## die on *any* error, so there is no error checking in this script
	##
	my $dvb = Linux::DVB::DVBT->new(
		'adapter_num'	=> $adap,
		'errmode'		=> 'message',
	) ;
	
	$dvb->config_path($config) if $config ;
	my $dev = $dvb->dvr_name ;

	## adapter
	info("selected $dvb_name") ;

	my @recargs ;	
	my ($channel) ;
	my ($file) ;
	my ($duration) ;
	my %file_options ;
	my %file_info ;
	
	## Get recordings from file
	if ($rec_file)
	{
		open my $fh, "<$rec_file" or die_error_mail($mailto, "Failed to open recording list file $rec_file : $!", "UNKNOWN", $rec_file, $log) ;		
		my $line ;
		while (defined($line=<$fh>))
		{
			chomp $line ;
			
			# skip comments
			next if ($line =~ /^\s*#/) ;

			# Line includes an offset
			my ($off, $ch, $f, $len) = (0, undef, undef, undef) ;				
			if ($line =~ /\+(\d+)\s+['"]([^'"]+)['"]\s+['"]([^'"]+)['"]\s+(\d+)/g)
			{
				($off, $ch, $f, $len) = ($1, $2, $3, $4) ;				
				$channel ||= $ch ;
				$file ||= $f ;
				$duration ||= $len ;
			}
			
			# no offset
			elsif ($line =~ /['"]([^'"]+)['"]\s+['"]([^'"]+)['"]\s+(\d+)/g)
			{
				($ch, $f, $len) = ($1, $2, $3, $4) ;				
				$channel ||= $ch ;
				$file ||= $f ;
				$duration ||= $len ;
			}

			## process if got something
			if ($f)
			{
				## check for extra options
				my %options ;
				while ($line =~ /\s*\-(\w+)\s+(\S+)/g)
				{
					$options{$1} = $2 ;
				}
				
				$file_options{$f} = {%options} ;
				
				## process
				process_args($ch, $f, $len, $off, \@recargs, \%options, \%file_info) ;
			}
		}
		close $fh ;
	}	
	
	## Get recordings from command line
	else
	{
		# process default args
		$channel = shift @ARGV ;
		$file = shift @ARGV ;
		$duration = shift @ARGV ;
		my %options = () ;
		if ($timeslip && defined($event) )
		{
			$options{'event'} = $event ;
			$options{'timeslip'} = $timeslip ;
			$options{'sliptype'} = $sliptype || 'end' ;
 		}
		$options{'title'} = $title if $title ;
		$options{'episode'} = $episode if $episode ;
		$options{'id'} = $id if $id ;
		process_args($channel, $file, $duration, 0, \@recargs, \%options, \%file_info) ;

		$file_options{$file} = {%options} ;


		# can only specify options for the first file
		$options{'event'} = 0 ;
		$options{'timeslip'} = 0 ;
		$options{'title'} = '';
		$options{'episode'} = '' ;
		$options{'id'} = '' ;
		
		while (scalar(@ARGV) >= 4)
		{
			my ($offset) = shift @ARGV ;
			$channel = shift @ARGV ;
			$file = shift @ARGV ;
			$duration = shift @ARGV ;
			process_args($channel, $file, $duration, $offset, \@recargs, \%options, \%file_info) ;

			$file_options{$file} = {} ;
		}
	}

    pod2usage("$0: No channel given.")  unless $channel ;
    pod2usage("$0: No filename given.")  unless $file ;
    pod2usage("$0: No duration given.")  unless $duration ;

Linux::DVB::DVBT::prt_data("File Info=", \%file_info) if $DEBUG >= 2 ;

	
	## Parse command line
	my @chan_spec ;
	my $error ;
	$error = $dvb->multiplex_parse(\@chan_spec, @recargs);

Linux::DVB::DVBT::prt_data("Multiplex parse args=", \@recargs, "chan_spec=", \@chan_spec) if $DEBUG >= 2 ;
	
	## Select the channel(s)
	info("selecting channel $channel...") ;
	$error = $dvb->multiplex_select(\@chan_spec) ;
	die_error_mail($mailto, "Failed to select channel : $error", $channel, $file, $log) if $error ;
	info("== Locked $dvb_name ==") ;

	## Get multiplex info
	my %multiplex_info = $dvb->multiplex_info() ;
Linux::DVB::DVBT::prt_data("Multiplex info=", \%multiplex_info) if $DEBUG >= 2  ;

	foreach my $file (sort { ($multiplex_info{'files'}{$a}{'offset'}||0) <=> ($multiplex_info{'files'}{$b}{'offset'}||0) } keys %{$multiplex_info{'files'}})
	{
		my $multiplex_href = $multiplex_info{'files'}{$file} ;
		info("  $file") ;

		my $prog_id = $file_info{$file}{'id'} ;
		if ($prog_id)
		{
			info("    ID      $prog_id") ;
		}

		info("    Chan     $multiplex_href->{channels}[0]") ;
		
		my $len = Linux::DVB::DVBT::Utils::secs2time($multiplex_href->{'duration'}) ;
		info("    Duration $len") ;
		
		if ($multiplex_href->{'offset'})
		{
			my $offset = Linux::DVB::DVBT::Utils::secs2time($multiplex_href->{'offset'}) ;
			info("    Offset  +$offset") ;
		}
		
		foreach my $pid_href (@{$multiplex_href->{'demux'}})
		{
			my $info = sprintf "    PID %5d [$pid_href->{'pidtype'}]", $pid_href->{'pid'} ;
			info($info) ;
		}
		info("") ;
		
		## Mark as started
		sql_start_status(\%dbh, $prog_id) ;
	}

	## Record
	foreach my $file (sort keys %{$multiplex_info{'files'}})
	{
		my $multiplex_href = $multiplex_info{'files'}{$file} ;
		info("recording to \"$multiplex_href->{destfile}\" for $multiplex_href->{duration} secs ...") ;
	}
	my $record_error = $dvb->multiplex_record(%multiplex_info) ;
	
	## Release DVB (for next recording)
	info("== Released $dvb_name ==") ;
	$dvb->dvb_close() ;
	
	## Stats
	info("Recording stats:") ;
	foreach my $file (sort keys %{$multiplex_info{'files'}})
	{
		my $href = $multiplex_info{'files'}{$file} ;
		info("  $file") ;
		my %stats ;
		foreach my $pid_href (@{$multiplex_info{'files'}{$file}{'pids'}})
		{
			my $info = sprintf "    PID %5d [$pid_href->{'pidtype'}] : %s errors / %s overflows / %s packets : Timeslip start %s secs, end %s secs", 
				$pid_href->{'pid'},
				$pid_href->{'errors'},
				$pid_href->{'overflows'},
				$pid_href->{'pkts'},
				$pid_href->{'timeslip_start_secs'},
				$pid_href->{'timeslip_end_secs'},
				 ;
				 
			info($info) ;
			
			foreach my $map_aref (
				['errors', 'statErrors'],
				['overflows', 'statOverflows'],
			)
			{
				my ($src, $dest) = @$map_aref ;
				my $val = int($pid_href->{$src}) ;	
				$stats{$dest} ||= 0 ;				
				$stats{$dest} += $val ;			
			}
			foreach my $map_aref (
				['timeslip_start_secs', 'statTimeslipStart'],
				['timeslip_end_secs', 'statTimeslipStart'],
			)
			{
				my ($src, $dest) = @$map_aref ;
				my $val = int($pid_href->{$src}) ;	
				$stats{$dest} ||= 0 ;				
				if ($stats{$dest} < $val)
				{
					$stats{$dest} = $val ;		
				}			
			}
		}
		info("") ;
		
		## Mark as recorded
		my $prog_id = $file_info{$file}{'id'} ;
		sql_update_status(\%dbh, $prog_id, 'recorded') ;
		sql_set_stats(\%dbh, $prog_id, \%stats) ;
	}
	
	
	
	# check for errors
	if ($record_error)
	{
		## whatever the error, report it then allow it through and use the length checking to see if we failed
		info("Warning: recording error $record_error") ;
	}

Linux::DVB::DVBT::prt_data("Post-Record Multiplex info=", \%multiplex_info) if $DEBUG >= 2  ;
	
	## Fix any errors
	foreach my $file (sort keys %{$multiplex_info{'files'}})
	{
		## filename 
		my ($name, $dir, $ext) = fileparse($file, '\..*') ;
		
		my $multiplex_href = $multiplex_info{'files'}{$file} ;
		$multiplex_href->{'original_ts'} = '' ;
		my $this_ok = 1 ;
		if ($multiplex_href->{'tsfile'})
		{
			$this_ok = repair_ts($multiplex_href->{'tsfile'}, $dir, $name, \$multiplex_href->{'original_ts'}) ;
		}
		elsif ($ext eq '.ts')
		{
			$this_ok = repair_ts($file, $dir, $name, \$multiplex_href->{'original_ts'}) ;
		}
		
		$ok &&= $this_ok ;
		
		if ($this_ok)
		{
			## Mark as repaired
			my $prog_id = $file_info{$file}{'id'} ;
			sql_update_status(\%dbh, $prog_id, 'repaired') ;
		}
	}
	$error = 1 unless $ok ;
	
	
	## transcode
	foreach my $file (sort keys %{$multiplex_info{'files'}})
	{
		my $multiplex_href = $multiplex_info{'files'}{$file} ;

		info("creating/checking \"$multiplex_href->{destfile}\" ...") ;
		$error ||= $dvb->multiplex_transcode(%multiplex_info) ; 
		
		# transcoding lines
		foreach my $line (@{$multiplex_href->{'lines'}})
		{
			info("$line") ;
		}
	
		# warning lines
		foreach my $line (@{$multiplex_href->{'warnings'}})
		{
			info("WARN: $line") ;
		}
	
		# error lines
		foreach my $line (@{$multiplex_href->{'errors'}})
		{
			info("ERROR: $line") ;
		}
	}

Linux::DVB::DVBT::prt_data("Post-Transcode Multiplex info=", \%multiplex_info) if $DEBUG >= 2  ;

	# now check error	
	if (!$error)
	{
		info("File durations have been checked ... OK") ;
		
		foreach my $file (sort keys %{$multiplex_info{'files'}})
		{
			my $multiplex_href = $multiplex_info{'files'}{$file} ;
	
			## Move TS file into trash dir
			if (!$force_ts)
			{
				if ($multiplex_href->{'tsfile'})
				{
					info("moving \"$multiplex_href->{srcfile}\" to TRASH ($trash) ...") ;
					my $this_ok = move("$multiplex_href->{srcfile}", "$trash") ;
					$ok &&= $this_ok ;
				}
			}
			if ($multiplex_href->{'original_ts'})
			{
				info("moving \"$multiplex_href->{'original_ts'}\" to TRASH ($trash) ...") ;
				my $this_ok = move($multiplex_href->{'original_ts'}, "$trash") ;
				$ok &&= $this_ok ;
			}
	
			die_error_mail($mailto, "failed to move : $!", $channel, $file, $log) unless $ok ;
	
		}
	}
	$error = 1 unless $ok ;
	
	if ($error)
	{
		## End
		die_error_mail($mailto, "Failed to complete", $channel, $file, $log) ;
	}

Linux::DVB::DVBT::prt_data("Pre-Addskip Multiplex info=", \%multiplex_info) if $DEBUG >= 2  ;


	## Advert removal
	if ($adskip)
	{
		foreach my $file (sort keys %{$multiplex_info{'files'}})
		{
			my $multiplex_href = $multiplex_info{'files'}{$file} ;
			if ($multiplex_href->{'video'})
			{
				my $split = remove_adverts($dvb, $multiplex_href->{'destfile'}, $multiplex_href->{'channels'}[0], $trash) ;
				if ($split)
				{
					## Mark as split
					my $prog_id = $file_info{$file}{'id'} ;
					sql_update_status(\%dbh, $prog_id, 'split') ;
				}
			}
		}
	}
	
	## Tag any MP3
	foreach my $file (sort keys %{$multiplex_info{'files'}})
	{
		my $multiplex_href = $multiplex_info{'files'}{$file} ;
		if (!$multiplex_href->{'video'} && $multiplex_href->{'audio'} && ($multiplex_href->{'destext'} eq '.mp3') )
		{
			my $ok = mp3tag($multiplex_href->{'destfile'}, $multiplex_href, $file_options{$file}) ;	
			if ($ok)
			{
				## Mark as tagged
				my $prog_id = $file_info{$file}{'id'} ;
				sql_update_status(\%dbh, $prog_id, 'mp3tag') ;
			}
		}
	}
	
	
	## End
	info("COMPLETE") ;
	foreach my $file (sort keys %{$multiplex_info{'files'}})
	{
		## Mark as complete
		my $prog_id = $file_info{$file}{'id'} ;
		sql_update_status(\%dbh, $prog_id, 'complete') ;
	}



#=================================================================================
# SUBROUTINES
#=================================================================================

#-----------------------------------------------------------------------------
sub process_args
{
	my ($channel, $file, $duration, $offset, $recargs_aref, $opts_href, $info_href) = @_ ;
	
	$opts_href ||= {} ;
	$offset =~ s/\+//g ;
	
	info("Channel:  $channel") ;
	info("File:     $file") ;
	info("Duration: $duration") ;
	info("Offset:   $offset") if $offset ;
	
	foreach my $opt (sort keys %$opts_href)
	{
		info("$opt = $opts_href->{$opt}") ;
	}

	## filename 
	my ($name, $dir, $ext) = fileparse($file, '\..*') ;
	
	if ($force_ts)
	{
		$ext = '.ts' ;
		$file = "$dir$name$ext" ;
	}

	## Convert duration to seconds
	my $seconds = Linux::DVB::DVBT::Utils::timesec2secs($duration) ;

	## Ensure duration is in correct format
	$duration = "0:0:$seconds" ;

	## Convert offset to seconds
	$seconds = Linux::DVB::DVBT::Utils::timesec2secs($offset) ;

	## Ensure duration is in correct format
	$offset = "0:0:$seconds" ;

	my $path = $file ;
	$path = "$rootdir/$file" if $rootdir ;
	push @$recargs_aref, "f=$path";
	push @$recargs_aref, "ch=$channel";
	push @$recargs_aref, "len=$duration";
	push @$recargs_aref, "offset=$offset";
	
	if ($opts_href->{'timeslip'})
	{
#		my $timeslip_secs = $opts_href->{'timeslip'} * 60 ;
		my $timeslip_secs = $opts_href->{'timeslip'} ;		# timeslip specified in minutes
		push @$recargs_aref, "max_timeslip=$timeslip_secs";
		push @$recargs_aref, "event=$opts_href->{'event'}";
		
		if ($opts_href->{'sliptype'})
		{
			push @$recargs_aref, "timeslip=$opts_href->{'sliptype'}";
		}
	}
	
	## Track options
	$info_href->{$file} = { %$opts_href } ;
}


#-----------------------------------------------------------------------------
sub repair_ts
{
	my ($tsfile, $dir, $name, $original_ts_ref) = @_ ;
	
	## Check for zero-length file
	if (! -s "$tsfile")
	{
		info("[tsrepair] Error: zero-length file \"$tsfile\"") ;
		return 
	}
	
	$$original_ts_ref = "$dir$name-original.ts" ;
	
	info("[tsrepair] Repairing \"$tsfile\" ...") ;
	my $this_ok = move("$tsfile", $$original_ts_ref) ;
	
	if ($this_ok)
	{
#		my @lines = `tsrepair '$$original_ts_ref' '$tsfile'` ;
#		foreach my $line (@lines)
#		{
#			chomp $line ;
#			info("[tsrepair] $line") ;
#		}


		## get information (including file duration)
		my %info = Linux::DVB::DVBT::TS::info($$original_ts_ref) ;
		my $info = sprintf "Duration: %02d:%02d:%02d, ", $info{'duration'}{'hh'}, $info{'duration'}{'mm'}, $info{'duration'}{'ss'} ;
		info("[tsrepair] $info") ;
		$info =	sprintf "Packets: %08d, ", $info{'total_pkts'} ;
		info("[tsrepair] $info") ;
			

		## Now repair the file
		my %stats = Linux::DVB::DVBT::TS::repair($$original_ts_ref, $tsfile) ;
		
		if (keys %stats)
		{
			my $error = "" ;
			my $errorcode = 0 ;
			if (exists($stats{'error'}))
			{
				$error = delete $stats{'error'} ;
				$errorcode = delete $stats{'errorcode'} ;
				
				## Ignore general TS error flag
				if ($error =~ /file/i)
				{
					# abort
				}
				else
				{
					$errorcode = 0 ;
				}
			}
			
			$this_ok = 0 unless $errorcode==0;
			
			info("[tsrepair] Repair Statistics:") ;
			if ($errorcode)
			{
				info("[tsrepair] ERROR: $error") ;
			}
			else
			{
				info("[tsrepair] INFO: $error") ;
			}
			foreach my $pid (sort {$a <=> $b} keys %stats)
			{
				info("[tsrepair]   PID $pid : $stats{$pid}{'errors'} errors repaired") ;
				foreach my $error_str (sort keys %{$stats{$pid}{'details'}})
				{
					info("[tsrepair]    * $error_str ($stats{$pid}{'details'}{$error_str})") ;
				}
			}
		}
		else
		{
			info("[tsrepair] No error statistics") ;
		}
	}
	info("[tsrepair] Repair done") ;

	return $this_ok ;
}

#-----------------------------------------------------------------------------
sub remove_adverts
{
	my ($dvb, $tsfile, $channel, $trash) = @_ ;
	
	my $split = 0 ;

	my $tuning_href = $dvb->get_tuning_info() ;

	## Get combined settings for this channel
	my $advert_settings_href = Linux::DVB::DVBT::Advert::channel_settings({}, $channel, $tuning_href) ;
	if (!Linux::DVB::DVBT::Advert::ok_to_detect($advert_settings_href))
	{
		info("[Advert] Skipping Ad Removal for \"$tsfile\" due to config settings") ;
		return $split ;
	}

	info("[Advert] Ad Removal for \"$tsfile\"") ;
	
	## create names
	my ($name, $dir, $ext) = fileparse($tsfile, '\..*') ;
	
	$dir = "$dir/$name" ;
	if (! -d $dir)
	{
		if (!mkpath([$dir], 0, 0755))
		{
			info("ERROR: unable to create dir $dir : $!") ;
			return $split ;
		}
	}
	my $detfile = "$dir/$name.det" ;
	my $csvfile = "$dir/$name.adv" ;
	my $cutfile = "$dir/$name.cut" ;
	my $dstfile = "$dir/$name.ts" ;
	
	## Set nice level
	my $pid = $$ ;
	my @nice = `renice +19 $pid` ;
	info("[Advert] set nice-ness:") ;
	foreach my $line (@nice)
	{
		info("[Advert] nice: $line") ;
	}
	
	# Read tuning info
	my $tuning_href = Linux::DVB::DVBT::Config::read($config); 
	
	# Add debug
	my $settings_href = {
		'debug' => $DEBUG,
	} ;
	
	## Detect
	info("[Advert] Detecting (saving as \"$detfile\")") ;
	my $results_href = Linux::DVB::DVBT::Advert::detect($tsfile, $settings_href, $channel, $tuning_href, $detfile) ;

	## save cut log
	open (STDOUT, ">$cutfile") ;
	# pipe advert debug into log file
	$Linux::DVB::DVBT::Advert::DEBUG = 1 ;
		
	## Analyse
	info("[Advert] Analysing (saving as \"$csvfile\")") ;
	my $expected_aref = undef ;
	my @cut_list = Linux::DVB::DVBT::Advert::analyse($tsfile, $results_href, $tuning_href, $channel, $csvfile, $expected_aref, $settings_href) ;
	$Linux::DVB::DVBT::Advert::DEBUG = 0 ;

	## save cut list
	print "Cut List:\n" ;
	foreach (@cut_list)
	{
		print "  pkt=$_->{start_pkt}:$_->{end_pkt}\n" ;
	}
	print "\n" ;

	## Cut
	if ($dstfile && $tsfile && @cut_list)
	{
		info("[Advert] Splitting into \"$dstfile\"") ;
		my $error = Linux::DVB::DVBT::Advert::ad_split($tsfile, $dstfile, \@cut_list) ;
		
		## I'll assume all is well and remove the original
		if (!$error)
		{
			++$split ;
			##info("moving \"$tsfile\" to TRASH ($trash) ...") ;
			##my $this_ok = move("$tsfile", "$trash/$name-ads.ts") ;
		}
	}
	else
	{
		info("[Advert] No valid adverts found for cutting. Advert removal stopping.") ;
	}
	
	return $split ;
}

#-----------------------------------------------------------------------------
sub mp3tag
{
	my ($file, $multiplex_href, $opts_href) = @_ ;
	
	my $ok = 1 ;

	info("[MP3TAG] Tagging \"$file\"") ;
	
	my $mp3 = MP3::Tag->new($file);

	my $this_year = (localtime(time))[5] + 1900 ;

	# Evoke flow displays:
	#  TIT2
	#  TALB
	#
	# TPE1 == Artist
	# TIT2 == Title
	# TALB == Album
	# TYER == Year
	$mp3->select_id3v2_frame_by_descr('TYER', $this_year); 
	$mp3->select_id3v2_frame_by_descr('TPE1', $multiplex_href->{'channels'}[0]); 
	$mp3->select_id3v2_frame_by_descr('TIT2', $opts_href->{'title'}) if $opts_href->{'title'} ; 
	$mp3->select_id3v2_frame_by_descr('TALB', $opts_href->{'episode'}) if $opts_href->{'episode'} ; 

	$mp3->update_tags();                  # Commit to file
	
	my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo() ;
	
	info("[MP3TAG] Title:  	$title") ;
	info("[MP3TAG] Artist:  $artist") ;
	info("[MP3TAG] Album:  	$album") ;
	info("[MP3TAG] Year:  	$year") ;
	info("[MP3TAG] Genre:  	$genre") ;
	info("[MP3TAG] Comment: $comment") ;
	
	info("[MP3TAG] Completed tagging \"$file\"") ;

	return $ok ;
}

#=================================================================================
# MYSQL
#=================================================================================

## NOTE: For SQL table, 'pid' refers to the program id

#UPDATE tbl SET flags=TRIM(',' FROM CONCAT(flags, ',', 'flagtoadd'))
#
#delete:
#UPDATE tbl SET flags=TRIM(',' FROM REPLACE(CONCAT(',', flags, ','), ',flagtoremove,', ','))

#-----------------------------------------------------------------------------
sub sql_connect
{
	my ($db_href) = @_ ;

	$db_href->{'dbh'} = 0 ;
	
	eval
	{
		# Connect
		my $dbh = DBI->connect("DBI:mysql:database=".$db_href->{'db'}.
					";host=".$db_href->{'host'},
					$db_href->{'user'}, $db_href->{'password'},
					{'RaiseError' => 1}) ;
					
		$db_href->{'dbh'} = $dbh ;
	};
	if ($@)
	{
		print STDERR "Unable to connect to database : $@\n" ;
	}
	
	return $db_href->{'dbh'} ;
}

#-----------------------------------------------------------------------------
sub sql_send
{
	my ($db_href, $sql) = @_ ;
	
	my $dbh = sql_connect($db_href) ;
	if ($dbh)
	{
		# Do query
		eval
		{
			print STDERR "sql_send($sql)\n" if $DBG_SQL ;			
			$dbh->do($sql) ;
		};
		if ($@)
		{
			print STDERR "SQL do error $@\nSql=$sql" ;
		}
	}
}

#-----------------------------------------------------------------------------
sub sql_update_status
{
	my ($db_href, $pid, $status) = @_ ;

	print STDERR "sql_update_status(pid=$pid, status=$status)\n" if $DBG_SQL ;
	
	return unless $pid ;
	
	# UPDATE tbl SET flags=TRIM(',' FROM CONCAT(flags, ',', 'flagtoadd'))
	my $sql = "UPDATE $db_href->{tbl} SET `status`=TRIM(',' FROM CONCAT(`status`, ',', '$status')), `changed`=CURRENT_TIMESTAMP" ;
	$sql .= " WHERE `pid`='$pid' AND `rectype`='dvbt'" ;
	
	sql_send($db_href, $sql) ;
}

#-----------------------------------------------------------------------------
sub sql_start_status
{
	my ($db_href, $pid) = @_ ;

	print STDERR "sql_start_status(pid=$pid)\n" if $DBG_SQL ;

	return unless $pid ;
	
	# UPDATE tbl SET flags=TRIM(',' FROM CONCAT(flags, ',', 'flagtoadd'))
	my $sql = "UPDATE $db_href->{tbl} SET `status`='started', `changed`=CURRENT_TIMESTAMP" ;
	$sql .= " WHERE `pid`='$pid' AND `rectype`='dvbt'" ;
	
	sql_send($db_href, $sql) ;
}



#-----------------------------------------------------------------------------
sub sql_set_stats
{
	my ($db_href, $pid, $stats_href) = @_ ;

	print STDERR "sql_set_stats(pid=$pid)\n" if $DBG_SQL ;

	return unless $pid ;
	
	my $values = "" ;
	foreach my $var (sort keys %$stats_href)
	{
		$values .= ", " if $values ;
		$values .= "`$var`='$stats_href->{$var}'" ;
	}
	
	my $sql = "UPDATE $db_href->{tbl} SET $values, `changed`=CURRENT_TIMESTAMP" ;
	$sql .= " WHERE `pid`='$pid' AND `rectype`='dvbt'" ;
	
	sql_send($db_href, $sql) ;
}

#-----------------------------------------------------------------------------
sub sql_set_error
{
	my ($db_href, $pid, $error) = @_ ;
	
	print STDERR "sql_set_error(pid=$pid, error=$error)\n" if $DBG_SQL ;

	return unless $pid ;
	
	sql_update_status($db_href, $pid, 'error') ;
	
	my $sql = "UPDATE $db_href->{tbl} SET `errorText`='$error', `changed`=CURRENT_TIMESTAMP" ;
	$sql .= " WHERE `pid`='$pid' AND `rectype`='dvbt'" ;
	
	sql_send($db_href, $sql) ;
}


#=================================================================================
# UTILITIES
#=================================================================================


#-----------------------------------------------------------------------------
# Format a timestamp for the reply
sub timestamp
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	return sprintf "%02d:%02d:%02d %02d/%02d/%04d", $hour,$min,$sec, $mday,$mon+1,$year+1900;
}


#---------------------------------------------------------------------------------
sub prompt
{
	my $timestamp = timestamp() ;
	my $prompt = "[$progname ($$) $timestamp $dvb_name]" ;
	
	return $prompt ;
}

#---------------------------------------------------------------------------------
sub info
{
	my ($msg) = @_ ;

	my $prompt = prompt() ;
	$msg =~ s/\n/\n$prompt /g ;
	print STDERR "$prompt $msg\n" ;
	
	my $timestamp = timestamp() ;
	push @info_lines, "$prompt $msg" ;
}


#---------------------------------------------------------------------------------
# send error email
sub error_mail
{
	my ($to, $error, $channel, $file, $log) = @_ ;
	
	my $prompt = prompt() ;
	
	my $data = "echo '$error'" ;
	
	my $tmpfile = "/tmp/dvbt-ffrec.$$" ;
	if (open my $fh, ">$tmpfile")
	{
		print $fh "$error\n\n" ;
		foreach (@info_lines)
		{
			print $fh "$_\n" ;
		}
		close $fh ;
		
		$data = "cat $tmpfile" ;	
	}
	else
	{
		$tmpfile = undef ;
	}
	
	`$data | mail -s '$prompt $channel $file Error' $to` ;
	
	# clean up
	unlink $tmpfile if $tmpfile ;
}

#---------------------------------------------------------------------------------
# send error email then exit
sub die_error_mail
{
	my ($to, $error, $channel, $file, $log) = @_ ;

	## Mark as failed
	if (exists($file_info{$file}))
	{
		my $prog_id = $file_info{$file}{'id'} ;
		sql_set_error(\%dbh, $prog_id, $error) ;
	}
	
	error_mail($to, $error, $channel, $file, $log) ;

	info("FATAL: $error") ;
	exit 1 ;
}



#=================================================================================
# END
#=================================================================================
__END__

=head1 NAME

dvbt-multirecord - Record program(s) to file

=head1 SYNOPSIS

dvbt-multirecord [options] channel filename duration(secs)

Options:

       -debug level         set debug level
       -verbose level       set verbosity level
       -help                brief help message
       -man                 full documentation
       -file file           read commands from a file
       -a dvb               set adapter number
       -cfg path            use config file search path
       -adskip en           set to 0 to disable advert detection
       -dir root            root directory
       
=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-verbose>

Set verbosity level. Higher values show more information.

=item B<-debug>

Set debug level. Higher levels show more debugging information (only really of any interest to developers!)


=back

=head1 DESCRIPTION

Script that uses the perl Linux::DVB::DVBT package to provide DVB-T adapter functions.

This script differs from B<dvbt-record> in that it illustrates the use of the DVR device by using it as an input
to ffmpeg. Here, ffmpeg is used to take the raw transport stream data and encapsulate it into an mpeg file.

Obviously, ffmpeg needs to be installed on the system for this script to work!

Specify the channel name to record, the filename of the recorded file (which may include a directory path
and the directories will be created as needed), and the duration of the recording. Note that the filename will be converted
to end with .mpeg extension.

The duration may be specified either as an integer number of B<seconds>, or in HH:MM format (for hours & minutes), or in
HH:MM:SS format (for hours, minutes, seconds).

The program uses a "fuzzy" search to match the specified channel name with the name broadcast by the network.
The case of the name is not important, and neither is whitespace. The search also checks for both numeric and
name instances of a number (e.g. "1" and "one").

For example, the following are all equivalent and match with the broadcast channel name "BBC ONE":

    bbc1
    BbC One
    b b c    1  


For full details of the DVBT functions, please see:

   perldoc Linux::DVB::DVBT
 
=cut
