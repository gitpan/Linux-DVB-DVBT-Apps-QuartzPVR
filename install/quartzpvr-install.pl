#!/usr/bin/perl
#
use strict ;

# Local
use App::Framework '+Sql +Run' ;
use Config::Crontab ;

use Linux::DVB::DVBT ;


# VERSION
our $VERSION = '1.00' ;


	# Create application and run it
	App::Framework->new() ;
	go() ;


#=================================================================================
# SUBROUTINES EXECUTED BY APP
#=================================================================================

#----------------------------------------------------------------------
# Main execution
#
sub app
{
	my ($app, $opts_href, $args_href) = @_ ;
	
	my %settings = get_config($app) ;
	
$app->prt_data("Settings", \%settings) ;

	## Must run this script as root
	if ($>) 
	{
		print STDERR "Error: This script must be run as root\n" ;
		exit 1 ;
	}
	
	my $webowner = "$settings{WEB_USER}:$settings{WEB_GROUP}" ;
	my $pvrowner = "$settings{PVR_USER}:$settings{PVR_GROUP}" ;

	## Create PVR user
	create_pvr_user($app, \%settings) ;

	## Create database
	create_database($app, \%settings) ;
	
	## Create dirs
	create_dirs($app, \%settings) ;
	
	## Copy files
	## Set privileges
	my @dirs = (
		['css',		$webowner, 0644],
		['js',		$webowner, 0644],
		['php',		$webowner, 0644],
		['scripts',	$pvrowner, 0755],
		['tpl',		$webowner, 0644],
	) ;
	install_files($app, \%settings, \@dirs) ;
	
	## Amend template files
	template_files($app, \%settings, "install/templates.txt") ;
	
	## Start server
	start_server($app, \%settings) ;
	
	## Do dvb-t scan
	dvbt_scan($app, \%settings) ;
	
	## Set channels
	dvbt_channels($app, \%settings) ;
	
	## Get listings
	dvbt_listings($app, \%settings) ;
}

#----------------------------------------------------------------------
# PVR Linux user
#
sub create_pvr_user
{
	my ($app, $settings_href) = @_ ;
	
	my $user = $settings_href->{'PVR_USER'} ;
	my $group = $settings_href->{'PVR_GROUP'} ;
	my $home = $settings_href->{'PVR_HOME'} ;
	
	my $uid = getpwnam($user) ; 
	my $gid = getgrnam($group) ;
	
	## Create group if required
	if (!$gid)
	{
		`groupadd $group` ;
	}
	
	## Create user if required
	if (!$uid)
	{
		`useradd -r -d $home -m -k /dev/null -g $group $user` ;
	}
	
	## Ensure crontab is initialised
	my $ct = new Config::Crontab( -owner => $user );
	$ct->read() ;
	my @dvbt_blocks = $ct->select(
								-type		=> 'comment',
								-data_re	=> '\@\[dvbt\-update\]' 
								) ;
								
Linux::DVB::DVBT::prt_data("dvbt_blocks=", \@dvbt_blocks) ;

	if (!@dvbt_blocks)
	{
		## Add block to crontab
		my $block = new Config::Crontab::Block ;
		$block->last(new Config::Crontab::Comment("# @[dvbt-update] Update the EPG")) ;
		$block->last(new Config::Crontab::Event(
				-active		=> 1,
				-minute 	=> 7,
				-hour	 	=> 4,
				-command	=> "$^X $settings_href->{'PVR_ROOT'}/scripts/dvbt-epg-sql.pl >> $settings_href->{'PVR_LOGDIR'}/dvbt_epg.log 2>&1",
		)) ;
		$ct->last($block) ;

		## Add block to crontab
		$block = new Config::Crontab::Block ;
		$block->last(new Config::Crontab::Comment("# @[dvbt-update] Update the scheduled programs")) ;
		$block->last(new Config::Crontab::Event(
				-active		=> 1,
				-minute 	=> 7,
				-hour	 	=> 6,
				-command	=> "$^X $settings_href->{'PVR_ROOT'}/scripts/dvb_record_mgr.pl -dbg-trace all -report 1 >> $settings_href->{'PVR_LOGDIR'}/dvb_record_mgr.log 2>&1",
		)) ;
		
		$ct->last($block) ;
		
		## Write crontab
		$ct->write()    
		  or do {
	        warn "Error: " . $ct->error . "\n";
	      };

print "Written crontab\n" ;	      
	      
	}
}


#----------------------------------------------------------------------
# MySQL
#
sub create_database
{
	my ($app, $settings_href) = @_ ;

	## Check for user
	my $temp0 = "tmp0-$$.sql" ;
	open my $fh, ">$temp0" or die "Error: Unable to create temp file : $!" ;
	print $fh <<SQL ;
SELECT user from mysql.user where user='$settings_href->{SQL_USER}';
SQL
	close $fh ;

	$app->run("mysql -uroot -p$settings_href->{SQL_ROOT_PASSWORD} < $temp0") ;
	my $results_aref = $app->run()->results ;
	my $status = $app->run()->status ;
	if ($status)
	{
		print "Error: MySQL error while loading $temp0\n" ;
		foreach (@$results_aref)
		{
			print "$_\n" ;
		}
		exit 1 ;
	}
	
	my $create_user = 1 ;
	if (@$results_aref)
	{
		$create_user = 0 ;
	}
	
	
	## Create user if required
	my $temp1 = "tmp1$$.sql" ;
	open my $fh, ">$temp1" or die "Error: Unable to create temp file : $!" ;
	if ($create_user)
	{
		print $fh <<SQL ;
	
CREATE USER '$settings_href->{SQL_USER}'\@'localhost' IDENTIFIED BY  '$settings_href->{SQL_PASSWORD}';
GRANT USAGE ON * . * TO  '$settings_href->{SQL_USER}'\@'localhost' IDENTIFIED BY  '$settings_href->{SQL_PASSWORD}' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `$settings_href->{DATABASE}` /*!40100 DEFAULT CHARACTER SET latin1 */;
GRANT ALL PRIVILEGES ON  `$settings_href->{DATABASE}` . * TO  '$settings_href->{SQL_USER}'\@'localhost' WITH GRANT OPTION ;

SQL
	}
	else
	{
		print $fh <<SQL ;
	
SET PASSWORD FOR '$settings_href->{SQL_USER}'\@'localhost' = PASSWORD('$settings_href->{SQL_PASSWORD}') ;
GRANT USAGE ON * . * TO  '$settings_href->{SQL_USER}'\@'localhost' IDENTIFIED BY  '$settings_href->{SQL_PASSWORD}' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `$settings_href->{DATABASE}` /*!40100 DEFAULT CHARACTER SET latin1 */;
GRANT ALL PRIVILEGES ON  `$settings_href->{DATABASE}` . * TO  '$settings_href->{SQL_USER}'\@'localhost' WITH GRANT OPTION ;

SQL
	}
	close $fh ;

	$app->run("mysql -uroot -p$settings_href->{SQL_ROOT_PASSWORD} < $temp1") ;
	$status = $app->run()->status ;
	if ($status)
	{
		print "Error: MySQL error while loading $temp1\n" ;
		$results_aref = $app->run()->results ;
		foreach (@$results_aref)
		{
			print "$_\n" ;
		}
		exit 1 ;
	}
	
	
	## Check for listings
	my $temp3 = "tmp3-$$.sql" ;
	open my $fh, ">$temp3" or die "Error: Unable to create temp file : $!" ;
	print $fh <<SQL ;
SELECT * from $settings_href->{DATABASE}.listings LIMIT 1 ;
SQL
	close $fh ;

	my $got_listings = 0 ;
	$app->run("mysql -uroot -p$settings_href->{SQL_ROOT_PASSWORD} < $temp0") ;
	my $results_aref = $app->run()->results ;
	my $status = $app->run()->status ;
	if (!$status)
	{
		if (@$results_aref)
		{
			$got_listings = 1 ;
		}
	}
	

	my $temp2 ;
	if ($got_listings)
	{
		print "Already got listings table, skipping\n" ;
	}
	else
	{
		print "Creating new tables ..\n" ;

		## Create tables	
		my $sql = $app->data("sql") ;
		$sql =~ s/\%DATABASE\%/$settings_href->{'DATABASE'}/g ;
		$temp2 = "tmp2$$.sql" ;
		open my $fh, ">$temp2" or die "Error: Unable to create temp file : $!" ;
		print $fh $sql ;
		close $fh ;
	
		$app->run("mysql -uroot -p$settings_href->{SQL_ROOT_PASSWORD} < $temp2") ;
		$status = $app->run()->status ;
		if ($status)
		{
			print "Error: MySQL error while loading $temp2\n" ;
			$results_aref = $app->run()->results ;
			foreach (@$results_aref)
			{
				print "$_\n" ;
			}
			exit 1 ;
		}
	}
	
	unlink $temp0 ;
	unlink $temp1 ;
	unlink $temp2 if $temp2 ;
	unlink $temp3 ;
}


#----------------------------------------------------------------------
# Directories
#
sub create_dirs
{
	my ($app, $settings_href) = @_ ;
	
	my $web_uid = getpwnam($settings_href->{'WEB_USER'}) ;
	my $web_gid = getgrnam($settings_href->{'WEB_GROUP'}) ;
	
	my $pvr_uid = getpwnam($settings_href->{'PVR_USER'}) ;
	my $pvr_gid = getgrnam($settings_href->{'PVR_GROUP'}) ;
	
	## Web
	foreach my $d (qw/PVR_ROOT/)
	{
		if (! -d $settings_href->{$d})
		{
			mkdir $settings_href->{$d} ;
			chmod 0755, $settings_href->{$d} ;
			chown $web_uid, $web_gid, $settings_href->{$d} ;
		}
	}
	
	## PVR
	foreach my $d (qw/VIDEO_DIR AUDIO_DIR PVR_LOGDIR/)
	{
		if (! -d $settings_href->{$d})
		{
			mkdir $settings_href->{$d} ;
			chmod 0755, $settings_href->{$d} ;
			chown $pvr_uid, $pvr_gid, $settings_href->{$d} ;
		}
	}
	
}

#----------------------------------------------------------------------
# Install
#
sub install_files
{
	my ($app, $settings_href, $dirs_aref) = @_ ;
	
	my $dest = $settings_href->{'PVR_ROOT'} ;
	
	print "Installing files:\n" ;
	
	foreach my $aref (@$dirs_aref)
	{
		my ($dir, $owner) = @$aref ;
		
		## copy directory
		print " * Installing files from $dir .. " ;
		$app->run("cp -pr $dir $dest") ;
		print "done\n" ;
		my $status = $app->run()->status ;
		if ($status)
		{
			print "Error copying files from $dir\n" ;
			exit 1 ;
		}
		
		## Set ownership
		$app->run("chown -R $owner $dest/$dir") ;
		$status = $app->run()->status ;
		if ($status)
		{
			print "Error setting ownership of $dest/$dir to $owner\n" ;
			exit 1 ;
		}
	}
	
	## Copy index file 
	$app->run("cp index.php $dest") ;
	

}

#----------------------------------------------------------------------
# Templates
#
sub template_files
{
	my ($app, $settings_href, $template_file) = @_ ;
	
	my %vars = (%$settings_href) ;
	
	$vars{'web_uid'} = getpwnam($settings_href->{'WEB_USER'}) ; 
	$vars{'web_gid'} = getgrnam($settings_href->{'WEB_GROUP'}) ;
	$vars{'pvr_uid'} = getpwnam($settings_href->{'PVR_USER'}) ; 
	$vars{'pvr_gid'} = getgrnam($settings_href->{'PVR_GROUP'}) ;
	$vars{'pvrdir'} = $settings_href->{'PVR_ROOT'} ;
	foreach my $field (keys %$settings_href)
	{
		$vars{lc $field} = $settings_href->{$field} ;
	}

	## read in control file
	my @templates ;
	my $line ;
	open my $fh, "<$template_file" or die "Error: Unable to read template control file $template_file : $!" ;
	while (defined($line=<$fh>))
	{
		chomp $line ;
		next if $line =~ m/^\s*#/ ;
		
		# "php/Config/Constants.inc", "$pvrdir/php/Config/Constants.inc", $web_uid, $web_gid, 0666
		my @fields = split(/,/, $line) ;
		if (@fields >= 5)
		{
			my $aref = [] ;
			foreach my $field (@fields)
			{
				$field =~ s/^\s+// ;
				$field =~ s/\s+// ;
				$field =~ s/^['"](.*)['"]$/$1/ ;
				
				$field =~ s/\$(\w+)/$vars{$1}/ge ;
				
				push @$aref, $field ;
			}
			push @templates, $aref ;
		}
	}
	close $fh ;
	
	## Process template files	
	print "Installing template files:\n" ;
	foreach my $aref (@templates)
	{
		my ($src, $dest, $uid, $gid, $mode) = @$aref ;
		
		$mode = oct($mode) ;

		print " * Installing template $src .. " ;
		
		# read
		local $/ ;
		open my $fh, "<install/$src" or die "Error: unable to read template $src : $!" ;
		my $data = <$fh> ;
		close $fh ;
		
		# translate
		$data =~ s/\%([\w_]+)\%/$settings_href->{$1}/ge ;
		
		# check destination directory
		my $dir = dirname($dest) ;
		if (! -d $dir)
		{
			mkpath([$dir], 0, 0755) ;
			chown $uid, $gid, $dir ;
		}
		
		# write
		open my $fh, ">$dest" or die "Error: unable to write template $dest : $!" ;
		print $fh $data ;
		close $fh ;
		
		# set perms
		chown $uid, $gid, $dest ;
		chmod $mode, $dest ;
		
print "\nSet $dest owner $uid:$gid  mode $mode\n" ;
		print "done\n" ;
		
	}	
	
}


#----------------------------------------------------------------------
sub start_server
{
	my ($app, $settings_href) = @_ ;

	print "Starting QuartzPVR server ..\n" ;
	system("/etc/init.d/quartzpvr-server restart") ;
}

#----------------------------------------------------------------------
sub dvbt_scan
{
	my ($app, $settings_href) = @_ ;

	print "Initialising DVB-T ..\n" ;
	
	## Create dvb 
	my $dvb = Linux::DVB::DVBT->new() ;
	my $tuning_href = $dvb->get_tuning_info() ;
#Linux::DVB::DVBT::prt_data("Current tuning info=", $tuning_href) ;
	$dvb = undef ;
	
	if ($tuning_href)
	{
		print " * DVB-T already initialised, skipping\n" ;
	}
	else
	{
		print " * Tuning DVB-T, this may take some time - please wait ..\n" ;
		system("dvbt-scan $settings_href->{'DVBT_FREQFILE'}") ;
	}
	
	
}

#----------------------------------------------------------------------
sub dvbt_channels
{
	my ($app, $settings_href) = @_ ;

	print "Updating DVB-T channels ..\n" ;
	system("$^X $settings_href->{'PVR_ROOT'}/scripts/dvbt-chans-sql.pl ")
	
}

#----------------------------------------------------------------------
sub dvbt_listings
{
	my ($app, $settings_href) = @_ ;


	## Check for listings
	my $temp0 = "tmp0-$$.sql" ;
	open my $fh, ">$temp0" or die "Error: Unable to create temp file : $!" ;
	print $fh <<SQL ;
SELECT * from $settings_href->{DATABASE}.listings LIMIT 1 ;
SQL
	close $fh ;

	$app->run("mysql -uroot -p$settings_href->{SQL_ROOT_PASSWORD} < $temp0") ;
	my $results_aref = $app->run()->results ;
	my $status = $app->run()->status ;
	if ($status)
	{
		print "Error: MySQL error while loading $temp0\n" ;
		foreach (@$results_aref)
		{
			print "$_\n" ;
		}
		exit 1 ;
	}
	
	my $got_listings = 0 ;
	if (@$results_aref)
	{
		$got_listings = 1 ;
	}

	if ($got_listings)
	{
		print "Already got DVB-T listings, skipping\n" ;
	}
	else
	{
		print "Gathering DVB-T listings (please wait) ..\n" ;
		system("$^X $settings_href->{'PVR_ROOT'}/scripts/dvbt-epg-sql.pl") ;
	}

	unlink $temp0 ;
}




#=================================================================================
# FUNCTIONS
#=================================================================================

#----------------------------------------------------------------------
sub get_config
{
	my ($app) = @_ ;

	my @config = $app->data('config') ;
	my %settings ;
	foreach my $line (@config)
	{
		if ($line =~ m/^\s*([\w_]+)\s*=\s*(.*)/)
		{
			my ($var, $val) = ($1, $2) ;
			$val =~ s/\s+$// ;
			$settings{$var} = $val ;
		}
	}
	return %settings ;
}


#=================================================================================
# SETUP
#=================================================================================
__DATA__

[SUMMARY]

Installs the Quartz PVR 


__DATA__ sql

USE `%DATABASE%`;

--
-- Table structure for table `channels`
--

DROP TABLE IF EXISTS `channels`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `channels` (
  `channel` varchar(256) NOT NULL COMMENT 'Channel name used by DVB-T',
  `display_name` varchar(256) NOT NULL COMMENT 'Displayed channel name',
  `chan_num` int(11) NOT NULL AUTO_INCREMENT COMMENT 'Channel number',
  `chan_type` set('tv','radio') NOT NULL DEFAULT 'tv' COMMENT 'TV or Radio',
  `show` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Whether to show this channel or not',
  `iplay` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Can the channel be recorded using get_iplayer',
  PRIMARY KEY (`chan_num`),
  KEY `type_show_num` (`chan_type`,`show`,`chan_num`)
) ENGINE=MyISAM AUTO_INCREMENT=729 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `iplay`
--

DROP TABLE IF EXISTS `iplay`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `iplay` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `rid` int(11) NOT NULL,
  `pid` varchar(128) NOT NULL COMMENT 'This is a pseduo PID (it''s got the correct date but may not relate to a real program)',
  `prog_pid` varchar(128) NOT NULL COMMENT 'This is a real (valid) program pid',
  `channel` varchar(128) NOT NULL,
  `record` int(11) NOT NULL,
  `date` date DEFAULT NULL,
  `start` time DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=73 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `listings`
--

DROP TABLE IF EXISTS `listings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `listings` (
  `pid` varchar(128) NOT NULL,
  `event` int(32) NOT NULL DEFAULT '-1',
  `title` varchar(128) NOT NULL,
  `date` date NOT NULL,
  `start` time NOT NULL,
  `duration` time NOT NULL,
  `episode` int(11) NOT NULL DEFAULT '0',
  `num_episodes` int(11) NOT NULL DEFAULT '0',
  `text` longtext NOT NULL,
  `channel` varchar(128) NOT NULL,
  `genre` varchar(256) DEFAULT '',
  `tva_prog` varchar(255) NOT NULL DEFAULT '-' COMMENT 'TV Anytime program id',
  `tva_series` varchar(255) NOT NULL DEFAULT '-' COMMENT 'TV Anytime series id',
  `audio` enum('unknown','mono','stereo','dual-mono','multi','surround') NOT NULL DEFAULT 'unknown' COMMENT 'audio channels',
  `video` enum('unknown','4:3','16:9','HDTV') NOT NULL DEFAULT 'unknown' COMMENT 'video screen size',
  `subtitles` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'subtitles available?',
  KEY `pid` (`pid`),
  KEY `chan_date_start_duration` (`channel`,`date`,`start`,`duration`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `multirec`
--

DROP TABLE IF EXISTS `multirec`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `multirec` (
  `multid` int(16) NOT NULL DEFAULT '0' COMMENT 'ID of multiplex recording group ; 0 = no group',
  `date` date DEFAULT '2001-01-00',
  `start` time DEFAULT '00:00:00',
  `duration` time NOT NULL DEFAULT '00:01:00',
  `adapter` int(11) NOT NULL DEFAULT '0',
  KEY `multid` (`multid`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `record`
--

DROP TABLE IF EXISTS `record`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `record` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `pid` varchar(128) NOT NULL,
  `title` varchar(128) NOT NULL,
  `date` date NOT NULL,
  `start` time NOT NULL,
  `duration` time NOT NULL,
  `episode` int(11) DEFAULT NULL COMMENT 'OBSOLETE: Remove?',
  `num_episodes` int(11) DEFAULT NULL COMMENT 'OBSOLETE: Remove?',
  `channel` varchar(128) NOT NULL,
  `adapter` tinyint(8) NOT NULL DEFAULT '0' COMMENT 'DVB adapter number - OBSOLETE: Remove?',
  `chan_type` varchar(256) DEFAULT 'tv',
  `record` int(11) NOT NULL COMMENT '[0=no record; 1=once; 2=weekly; 3=daily; 4=all(this channel); 5=all, 6=series] + [DVBT=0, FUZZY=0x20 (32), DVBT+IPLAY=0xC0 (192), IPLAY=0xE0 (224)] ',
  `priority` int(11) NOT NULL DEFAULT '50' COMMENT 'Set priority of recording: 1 is highest; 100 is lowest',
  `tva_series` varchar(255) NOT NULL DEFAULT '-',
  `tva_prog` varchar(255) NOT NULL DEFAULT '-' COMMENT 'TV Anytime program id',
  `pathspec` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path specification: varoables are replaced for each recording',
  PRIMARY KEY (`id`),
  KEY `pid` (`pid`)
) ENGINE=MyISAM AUTO_INCREMENT=606 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recorded`
--

DROP TABLE IF EXISTS `recorded`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `recorded` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `pid` varchar(128) NOT NULL,
  `rid` int(11) NOT NULL COMMENT 'Record ID',
  `ipid` varchar(128) NOT NULL DEFAULT '-' COMMENT 'IPLAY: The IPLAYER id (e.g. b00r4wrl)',
  `rectype` enum('dvbt','iplay') NOT NULL COMMENT 'Recording type',
  `title` varchar(128) NOT NULL,
  `text` varchar(255) NOT NULL DEFAULT '',
  `date` date NOT NULL,
  `start` time NOT NULL,
  `duration` time NOT NULL,
  `channel` varchar(128) NOT NULL,
  `adapter` tinyint(8) NOT NULL DEFAULT '0' COMMENT 'DVB adapter number',
  `type` enum('tv','radio') NOT NULL DEFAULT 'tv' COMMENT 'Type of recording',
  `record` int(11) NOT NULL COMMENT '[0=no record; 1=once; 2=weekly; 3=daily; 4=all(this channel); 5=all, 6=series] + [DVBT=0, FUZZY=0x20 (32), DVBT+IPLAY=0xC0 (192), IPLAY=0xE0 (224)] ',
  `priority` int(11) NOT NULL COMMENT 'Set priority of recording: 1 is highest; 100 is lowest',
  `genre` varchar(255) NOT NULL DEFAULT '',
  `tva_prog` varchar(255) NOT NULL DEFAULT '' COMMENT 'TV Anytime program id',
  `tva_series` varchar(255) NOT NULL DEFAULT '' COMMENT 'TV Anytime series id',
  `file` varchar(255) NOT NULL COMMENT 'Recorded filename',
  `changed` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Last modification date/time',
  `status` set('started','recorded','error','repaired','mp3tag','split','complete') NOT NULL DEFAULT '' COMMENT 'State of recording',
  `statErrors` int(11) NOT NULL DEFAULT '0' COMMENT 'Recording error count',
  `statOverflows` int(11) NOT NULL DEFAULT '0' COMMENT 'Recording overflow count',
  `statTimeslipStart` int(11) NOT NULL DEFAULT '0' COMMENT 'Seconds timeslipped start of recording',
  `statTimeslipEnd` int(11) NOT NULL DEFAULT '0' COMMENT 'Seconds timeslipped recordign end',
  `errorText` varchar(255) NOT NULL DEFAULT '' COMMENT 'Summary of any errors',
  PRIMARY KEY (`id`),
  KEY `pid` (`pid`),
  KEY `pid_rectype` (`pid`,`rectype`)
) ENGINE=MyISAM AUTO_INCREMENT=606 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `schedule`
--

DROP TABLE IF EXISTS `schedule`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `schedule` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `rid` int(11) NOT NULL,
  `pid` varchar(128) NOT NULL,
  `channel` varchar(128) NOT NULL,
  `record` int(11) NOT NULL,
  `date` date DEFAULT NULL COMMENT 'DEBUG ONLY!',
  `start` time DEFAULT NULL COMMENT 'DEBUG ONLY!',
  `priority` int(11) NOT NULL DEFAULT '10' COMMENT 'Lower numbers are higher priority',
  `adapter` int(11) NOT NULL DEFAULT '0',
  `multid` varchar(128) NOT NULL DEFAULT '0' COMMENT 'ID of multiplex recording group ; 0 = no group',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=47 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;



__DATA__ config

AUDIO_DIR = /served/stories
DATABASE = quartzpvr
DATE_TZ = TZ=GMT
DVBT_FREQFILE = /usr/share/dvb/dvb-t/uk-Oxford
PERL_BIN = /usr/bin/perl
PVR_GROUP = video
PVR_LOGDIR = /var/log/quartzpvr
PVR_ROOT = /var/www/quartzpvr
PVR_USER = quartzpvr
SERVER_PORT = 21328
SQL_PASSWORD = qp30763
SQL_ROOT_PASSWORD = zzsqlroot
SQL_USER = quartzpvr
VIDEO_DIR = /served/videos/PVR
WEB_GROUP = www-data
WEB_ROOT = /var/www
WEB_USER = www-data