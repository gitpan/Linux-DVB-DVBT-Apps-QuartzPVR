#use 5.008008;
use 5.006;
use ExtUtils::MakeMaker qw(prompt WriteMakefile);
use Config;
use strict;

use lib './plib' ;
use Makeutils ;


use Data::Dumper ;


	my $clib = "./clib" ;

	# Set up info for this module
	my $modinfo_href = init('Linux-DVB-DVBT-Apps-QuartzPVR') ;

	# See if newer version is available
	check_new_version() ;

	## Options
	get_makeopts() ;

	## Check for current settings
##	get_config() ;
	
	
	## get distribution
	my $dist = distribution_info() ;


	
	## get webserver info
	my ($webuser, $webgroup, $webroot) = webserver_info($dist) ;
print "Dist=$dist, web=$webuser:$webgroup root=$webroot\n" ;	
	my %settings = (
	
		'WEB_USER'		=> $webuser,
		'WEB_GROUP'		=> $webgroup,
		'WEB_ROOT'		=> $webroot,
	) ;

	## read in existing install script settings
	my $install_script = "install/quartzpvr-install.pl" ;
	read_install_script($install_script, \%settings) ;

	## get settings from user
	get_settings(\%settings) ;
	
#print "Dist=$dist, web=$webuser:$webgroup root=$webroot\n" ;	
print Data::Dumper->Dump(["Settings", \%settings]) ;


	## Update install
	update_install_script($install_script, \%settings) ;
	

	## Programs to install
#	add_install_progs("script/", [
#		qw/dvbt-ts-repair dvbt-ts-pics dvbt-ts-cut dvbt-ts-info/
#	]);

	

	## Do any cleanup
	process_makeopts() ;
	
	
	# See lib/ExtUtils/MakeMaker.pm for details of how to influence
	# the contents of the Makefile that is written.
	WriteMakefile(
	    NAME              => $modinfo_href->{'mod'},
	    VERSION_FROM      => "lib/$modinfo_href->{'modpath'}.pm", # finds $VERSION
	    PREREQ_PM         => {
			'File::Basename'	=> 0,
			'File::Path' 		=> 0,
			'File::Spec' 		=> 0,
			'POSIX'			=> 0,
			'Test::Pod::Coverage'	=> 1.08,
			'Pod::Coverage' => 0.18,
			'Test::Pod' => 1.22,
			'Data::Dumper',
			
			'Linux::DVB::DVBT' => 2.10,
			'Linux::DVB::DVBT::Advert' => 0.03,
			'App::Framework' => 1.04,
			
			'Config::Crontab',
			'Date::Manip',
			
	    }, # e.g., Module::Name => 1.1
	    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
	      (ABSTRACT_FROM  => "lib/$modinfo_href->{'modpath'}.pm", # retrieve abstract from module
	       AUTHOR         => 'Steve Price <cpan@quartz-net.co.uk>') : ()),
	    LIBS              => [], # e.g., '-lm'
	    INC               => $modinfo_href->{'includes'},
#	    EXE_FILES         => $modinfo_href->{'programs'},
	 
	);


	exit 0 ;


#-----------------------------------------------------------------------------------------------------------------------
sub MY::installbin 
{
"
pure_install :: 
	$^X $install_script

" ;
}


#-----------------------------------------------------------------------------------------------------------------------
sub MY::makemakerdflt 
{
	my $makemakerdflt = get_makemakerdflt() ;
	return $makemakerdflt ;
}

#-----------------------------------------------------------------------------------------------------------------------
sub MY::postamble {
'

## Optional doxygen documentation 
doxygen: FORCE
	cd doxygen && doxygen

## Author target: preview CPAN documentation
cpandoc: FORCE
	perl -MPod::Simple::HTMLBatch -e Pod::Simple::HTMLBatch::go . pod/batch
	cp pod/html_files/style.css pod/batch/_black_with_blue_on_white.css

';
}


#----------------------------------------------------------------------
# Work out/guess distribution
#
sub distribution_info
{
print "distribution_info\n" ;		
	my $dist ;
	my $reldir = '/etc' ;
	foreach my $rel (glob("$reldir/*-release"))
	{
print "Dist dir: $rel\n" ;		
		if ($rel =~ m%^$reldir/(\w+)\-release%)
		{
			my $this_dist = $1 ;
print " + dist file $this_dist\n" ;		
			if ($this_dist eq 'lsb')
			{
			    if (open my $fh, "<$rel")
			    {
				    my $info = '';
				    while (defined($info=<$fh>))
				    {
				        chomp $info;
				        if ($info =~ m/DISTRIB_ID\s*=\s*(.*)/)
				        {
				        	$dist = lc $1 ;
print " + + dist = $dist\n" ;		
				        	last ;
				        }
				    }
			    }
			}
			else
			{
				$dist = lc $this_dist ;
				last ;
			}
		}
	}
	return $dist ;
}

#----------------------------------------------------------------------
# Work out webserver user
#
sub webserver_info
{
	my ($dist) = @_ ;
print "web_info($dist)\n" ;		
	
	## user
	my ($webuser, $webgroup) ;
	foreach my $server (qw/apache http/)
	{ 
print " + server $server\n" ;		
		my @results = `ps -ef | grep -i $server | grep -v grep` ;
		foreach my $line (@results)
		{
			chomp $line ;
print " + + $line\n" ;		
			if ($line =~ /^(\S+)\s+/)
			{
				my $user = $1 ;
print " + + + user=$user\n" ;		
				if ($user ne 'root')
				{
					## Check valid user and get group if so
					# account:password:UID:GID:GECOS:directory:shell
					my @ufields = getpwnam($user) ;
					if (@ufields >= 7)
					{
						my $gid = $ufields[3] ;
						
						# group_name:passwd:GID:user_list
						my $grp = getgrgid($gid);
						if ($grp)
						{
							## got user & group
							$webuser = $user ;
							$webgroup = $grp ;

print " + + + webuser=$webuser webgroup=$webgroup\n" ;

							last ;
						}
					}
				}
			}
			last if $webuser ;
			
		} # each line
		
		last if $webuser ;
		
	} # each server
	
	## server root
	my $webroot = "/var/www" ;
	if ($dist eq 'suse')
	{
		$webroot = "/srv/www/htdocs" ;
	}
	
	
	return ($webuser, $webgroup, $webroot) ;
}

#----------------------------------------------------------------------
sub get_settings
{
	my ($settings_href) = @_ ;
	
	my @settings = (
[ "SQL_ROOT_PASSWORD",	undef,								"MySQL root user password so I can create the pvr database"],
[ "DVBT_FREQFILE",		undef,								"full path to DVB-T tuning frequency file (usually under /usr/share/dvb/dvb-t)"],
[ "SERVER_PORT", 		"21328",							"TCP port of the new PVR server that I will install"],
[ "WEB_USER", 			$settings_href->{'WEB_USER'},		"user name of the web server"],
[ "WEB_GROUP", 			$settings_href->{'WEB_GROUP'},		"group name of the web server"],
[ "SQL_USER", 			"quartzpvr",						"username of the MySQL pvr database owner"],
[ "SQL_PASSWORD",		"qp".$$,							"password of the MySQL pvr database owner"],
[ "PVR_USER", 			"quartzpvr",						"Linux user name created for recording"],
[ "PVR_GROUP", 			"video",							"Linux group name for PVR_USER"],
[ "PVR_LOGDIR", 		"/var/log/quartzpvr",				"location of PVR logs"],
[ "DATABASE", 			"quartzpvr",						"PVR database name"],
[ "VIDEO_DIR", 			"/var/lib/quartzpvr/video",			"Video recording top-level directory"],
[ "AUDIO_DIR", 			"/var/lib/quartzpvr/audio",			"Audio recording top-level directory"],
[ "PVR_ROOT", 			"$settings_href->{'WEB_ROOT'}/quartzpvr", "Installation directory. This is where all of the PVR software is installed."],

	) ;
	
	$settings_href->{'PERL_BIN'} = $^X ;
	$settings_href->{'DATE_TZ'} = "TZ=GMT" ;
	
print Data::Dumper->Dump(["Settings", \%settings]) ;	
	
	 
	## get any new settings
	foreach my $aref (@settings)
	{
		my ($var, $default, $desc) = @$aref ;
#		print "Default=$default\n" ;

		## Amend defaults with existing settings
		if ($settings_href->{$var})
		{
			$default = $settings_href->{$var} ;
		}
		my $val = $default || "" ;
		
		do
		{
			print "$var: Please enter the $desc [$val]: " ;
			my $ans = <STDIN> ;
			chomp $ans ;
			if ($ans)
			{
				$val = $ans ;
			}
		
		} while (!$val) ;
		
		$settings_href->{$var} = $val ;
	}
	
}


#----------------------------------------------------------------------
sub update_install_script
{
	my ($install_script, $settings_href) = @_ ;

	## Protect file
	chmod 0700, $install_script ;

	## Read in file
	my @lines ;
	{
	    local( $/ ) ;
    	open( my $fh, $install_script ) or die "Error: reading install script file $install_script : $!" ;
		my $lines = <$fh> ;
		close $fh ;

		@lines = split(/\n/, $lines) ;
	}

	## Amend config data section
	my $config_line = 0 ;
	for ($config_line = 0 ; $config_line < @lines; ++$config_line)
	{
#		print "$config_line :: $lines[$config_line]\n" ;
		if ($lines[$config_line] =~ /^\s*__DATA__\s+config/)
		{
#			print " >>>> Found config!\n" ;
			last ;
		}
	}
	$#lines = ++$config_line ;
	
	foreach my $var (sort keys %$settings_href)
	{
		push @lines, "$var = $settings_href->{$var}" ;
	}
	
	
	## Write file
   	open( my $fh, ">$install_script" ) or die "Error: writing install script file $install_script : $!" ;
	foreach (@lines)
	{
		print $fh "$_\n" ;
	}
	close $fh ;
}


#----------------------------------------------------------------------
sub read_install_script
{
	my ($install_script, $settings_href) = @_ ;

	## Read in file
	my @lines ;
	{
	    local( $/ ) ;
    	open( my $fh, $install_script ) or die "Error: reading install script file $install_script : $!" ;
		my $lines = <$fh> ;
		close $fh ;

		@lines = split(/\n/, $lines) ;
	}

	## Amend config data section
	my $config_line = 0 ;
	for ($config_line = 0 ; $config_line < @lines; ++$config_line)
	{
		if ($lines[$config_line] =~ /^\s*__DATA__\s+config/)
		{
			last ;
		}
	}
	

	for (++$config_line ; $config_line < @lines; ++$config_line)
	{
		if ($lines[$config_line] =~ /^\s*(\w+)\s*=\s*(.*)/)
		{
			my ($var, $val) = ($1, $2) ;
			$val =~ s/\s+$// ;
			$settings_href->{$var} = $val ;
		}
	}


}

