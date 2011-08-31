#!%PERL_BIN% -w
package Linux::DVB::DVBT::Apps::QuartzPVR ;

use strict ;
use base qw(Net::Server::Fork);

	my %COMMANDS = (
	
		'dvb_record_mgr'		=> $^X . ' %PVR_ROOT%/scripts/dvb_record_mgr.pl',
		
	) ;


	# Example:
	#
	#    #!/usr/bin/perl -w -T
	#
	#    package MyPackage;
	#    use strict;
	#    use base qw(Net::Server);
	#
	#
	#    sub process_request {
	#       #...code...
	#    }
	#
	#    my $server = MyPackage->new({
	#        key1 => 'val1',
	#    });
	#
	#    $server->run;
	#
	#-----------------------------------------------------------------------------------------------------------------------------------
	# The process flow is written in an open, easy to override, easy to hook, fashion. The basic flow is shown below. This is the flow of the 
	# $self->run method.
	#
	# $self->run
	#
	#  $self->configure_hook;
	#
	#  $self->configure(@_);
	#
	#  $self->post_configure;
	#
	#  $self->post_configure_hook;
	#
	#  $self->pre_bind;
	#
	#  $self->bind;
	#
	#  $self->post_bind_hook;
	#
	#  $self->post_bind;
	#
	#  $self->pre_loop_hook;
	#
	#  $self->loop;
	#
	#	  ### routines inside a standard $self->loop
	#	  $self->accept;
	#	  $self->run_client_connection;
	#
	#		  # During the client processing phase ($self->run_client_connection), the following represents the program flow:
	#		
	#		  $self->post_accept;
	#		
	#		  $self->get_client_info;
	#		
	#		  $self->post_accept_hook;
	#		
	#		  if( $self->allow_deny
	#		
	#		      && $self->allow_deny_hook ){
	#		
	#**		    $self->process_request;
	#		
	#		  }else{
	#		
	#		    $self->request_denied_hook;
	#		
	#		  }
	#		
	#		  $self->post_process_request_hook;
	#		
	#		  $self->post_process_request;
	#		
	#	  $self->done;
	#
	#  $self->pre_server_close_hook;
	#
	#  $self->server_close;
	#
	#The server then exits.
	#

    my $server = Linux::DVB::DVBT::Apps::QuartzPVR->new({
#        port 		=> ['%SERVER_PORT%'],
#		user 		=> '%PVR_USER%',
#		group 		=> '%PVR_GROUP%',
#        log_file 	=> '/var/log/quartzpvr-server.log',

		conf_file => '/etc/quartzpvr/quartzpvr-server.conf',
    });

    $server->run() ;



## Override

    sub process_request 
    {
        my $self = shift;

		$self->log(1, "New connection\n") ;
		
		my $cmd = <STDIN> ;
		chomp $cmd ;
#$self->log(1, "GOT CMD: $cmd\n") ;
		my $args = "" ;
		if ($cmd =~ /^(\w+)\s+(.*)/)
		{
			($cmd, $args) = ($1, $2) ;
		}
#$self->log(1, "cmd='$cmd' args='$args'\n") ;
		
		if (exists($COMMANDS{$cmd}))
		{
			my $fullcmd = $COMMANDS{$cmd} ;

			$self->log(1, "CMD: $fullcmd $args\n") ;
			my @lines = `$fullcmd $args 2>&1` ;
			$self->log(2, "CMD Complete\n") ;
			
			for my $line (@lines)
			{
				chomp $line ;
				$self->log(3, "[cmd] $line\n") ;
				print "$line\n" ;
			}
		}
		
		$self->log(1, "Connection closed\n") ;
    }


## New
