package Linux::DVB::DVBT::Apps::QuartzPVR ;

=head1 NAME

Linux::DVB::DVBT::Apps::QuartzPVR - PVR Application 

=head1 SYNOPSIS

	use Linux::DVB::DVBT::Apps::QuartzPVR ;
  
	print "Verion: " . Linux::DVB::DVBT::Apps::QuartzPVR::version() . "\n" ;
	

=head1 DESCRIPTION

This is a complete PVR application that uses a web frontend for TV listings display and for
managing recordings.

=cut


#============================================================================================
# USES
#============================================================================================
use strict ;

#============================================================================================
# EXPORTER
#============================================================================================
require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw/
	version
/ ;


#============================================================================================
# GLOBALS
#============================================================================================
our $VERSION = '0.01' ;


#============================================================================================

#============================================================================================

=head2 Functions

=over 4

=cut


#-----------------------------------------------------------------------------

=item B<version()>

Returns current application version.


=cut

sub version
{
	
	return $VERSION ;
}




# ============================================================================================
# END OF PACKAGE


1;

__END__

=back

=head1 ACKNOWLEDGEMENTS

=head2 jQuery

This program uses the jQuery Javascript library:

 * jQuery JavaScript Library v1.4
 * http://jquery.com/
 *
 * Copyright 2010, John Resig
 * Dual licensed under the MIT or GPL Version 2 licenses.
 * http://docs.jquery.com/License
 *
 * Includes Sizzle.js
 * http://sizzlejs.com/
 * Copyright 2010, The Dojo Foundation
 * Released under the MIT, BSD, and GPL Licenses.
 *
 * Date: Wed Jan 13 15:23:05 2010 -0500


=head1 AUTHOR

Steve Price

Please report bugs using L<http://rt.cpan.org>.

=head1 BUGS

None that I know of!

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Steve Price

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

