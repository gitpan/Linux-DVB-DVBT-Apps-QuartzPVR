package TVGuide::DVB ;

=head1 NAME

TVGuide::DVB - DVB-T utils

=head1 SYNOPSIS

use TVGuide::DVB ;


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

our $VERSION = "1.000" ;

#============================================================================================
# USES
#============================================================================================
use Data::Dumper ;
use Linux::DVB::DVBT ;

use TVGuide::Base::DbgProf ;
use TVGuide::Base::DbgTrace ;
use TVGuide::Time ;
use TVGuide::Prog ;
use TVGuide::Series ;

#============================================================================================
# GLOBALS
#============================================================================================

our $debug = 0 ;
our $tuning_href ;
our $channels_aref ;
our %chan_to_tsid ;
our %tsid_chans ;


#============================================================================================
# FUNCTIONS
#============================================================================================

BEGIN {
	my $dvb = Linux::DVB::DVBT->new() ;
	$tuning_href = $dvb->get_tuning_info() ;
	$channels_aref = $dvb->get_channel_list() ;

	foreach my $chan_href (@$channels_aref)
	{
		my $channel_name = $chan_href->{'channel'} ;
		my $tsid = $tuning_href->{'pr'}{$channel_name}{'tsid'} ;

		# store lookup info
		$chan_to_tsid{$channel_name} = $tsid ;
		$tsid_chans{$tsid} ||= [] ;
		push @{$tsid_chans{$tsid}}, $channel_name ;
	}
	
	$dvb->dvb_close() ;
}


#---------------------------------------------------------------------
sub lookup_channel
{
	my ($channel_name, $tuning_href) = @_ ;
	
	$channel_name = _channel_alias($channel_name, $tuning_href->{'aliases'}) ;
	my $found_channel_name = _channel_search($channel_name, $tuning_href->{'pr'}) ;	
	
	return $found_channel_name ;
}

#---------------------------------------------------------------------
# Given a channel name, find the multiplex that the channel belongs to 
# and return a list of ALL the channels in the multiplex
sub multiplex_channels
{
	my ($chan) = @_ ;
	my %channels = () ;
	
	if (exists($chan_to_tsid{$chan}))
	{
		my $tsid = $chan_to_tsid{$chan} ;
		my $chans_aref = $tsid_chans{$tsid} ;
		
		%channels = map { $_ => $tsid } @$chans_aref ;
	}
	
	return %channels ;
}


#============================================================================================
# DEBUG
#============================================================================================
#


# ============================================================================================
# END OF PACKAGE
1;

__END__


