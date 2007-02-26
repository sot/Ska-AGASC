#!/usr/bin/env /proj/sot/ska/bin/perlska

#use Ska::AGASC;
require '/proj/gads6/jeanproj/Ska-AGASC/lib/Ska/AGASC.pm';
use strict;
use warnings;
use Getopt::Long;

my %par;

GetOptions( \%par,
	    'help!',
            'datetime=s',
	    'ra|r=s',
            'dec|d=s',
	    'radius|w=s',
	    'mag_limit=s',
	    'old_format!',
	    'do_not_pm_correct_retrieve|nc!',
           ) ||
    exit( 1 );

usage(1) if $par{help};

use Data::Dumper;
#print Dumper %par;

my $agasc_region = Ska::AGASC->new(\%par);

my @star_list = $agasc_region->list_ids();
for my $agasc_id (@star_list){
    my $star = $agasc_region->get_star($agasc_id);
    if ($par{old_format}){
	my @fields = (
		      $agasc_id,
		      $star->ra(), 
		      $star->dec(), 
		      $star->pos_err(),
		      $star->pos_catid(),
		      $star->epoch(),
		      $star->pm_ra(),
		      $star->pm_dec(),
		      $star->pm_catid(),
		      $star->plx(),
		      $star->plx_err(),
		      $star->plx_catid(),
		      $star->mag_aca(),
		      $star->mag_aca_err(),
		      $star->class(),
		      $star->mag(),
		      $star->mag_err(),
		      $star->mag_band(),
		      $star->mag_catid(),
		      $star->color1(),
		      $star->color1_err(),
		      $star->c1_catid(),
		      $star->color2(),
		      $star->color2_err(),
		      $star->c2_catid(),
		      $star->rsv1(),
		      $star->rsv2(),
		      $star->rsv3(),
		      $star->var(),
		      $star->var_catid(),
		      $star->aspq1(),
		      $star->aspq2(),
		      $star->aspq3(),
		      $star->acqq1(),
		      $star->acqq2(),
		      $star->acqq3(),
		      $star->acqq4(),
		      $star->acqq5(),
		      $star->acqq6(),
		      $star->xref_id1(),
		      $star->xref_id2(),
		      $star->xref_id3(),
		      $star->xref_id4(),
		      $star->xref_id5(),
		      $star->rsv4(),
		      $star->rsv5(),
		      $star->rsv6(),
		      );
	for my $i (0 .. $#fields){
	    if (defined $fields[$i] ){
		print "$fields[$i] ";
	    }
	    else{
		print "field[$i]=undef ";
	    }
	}
	print "\n";
    }
    else{
	printf("id: %  s \t ra:% 3.2f \t dec:% 3.2f \t mag_aca:% 3.2f \t class:%d \n", 
	       $agasc_id, 
	       $star->ra_pmcorrected(), 
	       $star->dec_pmcorrected(), 
	       $star->mag_aca(),
	       $star->class(),
	       );
    }
}


##***************************************************************************
sub usage
##***************************************************************************
{
    my ( $exit ) = @_;
    local $^W = 0;
    require Pod::Text;
    Pod::Text::pod2text( '-75', $0 );
    exit($exit) if ($exit);
}

=pod

=head1 NAME

mp_get_agasc.pl - retrieve and print all objects from AGASC within a specified radius of a sky position

=head1 SYNOPSIS

B<mp_get_agasc.pl> [I<options>] 

=head1 OPTIONS

=over 4

=item B<-help>

Print this help information

=item B<-ra> B<-r>

RA of sky position; degrees

=item B<-dec> B<-d>

DEC of sky position; degrees

=item B<-radius> B<-w>

radius of cone to retrieve; degrees

=item B<-datetime>

Time to use for proper motion correction.  Chandra Seconds, YYYY:DOY, and YYYYMonDD formats
are all acceptable.  In the absence of a specified datetime, the current time at execution 
will be used. 

=item B<-mag_limit>

faint limit for retrieval query; objects with a mag_aca dimmer than this limit will not be retrieved
If not specified, all objects will be printed.

=item B<-do_not_pm_correct_retrieve> B<-nc>

This overrides the default behavior.  Default behavior is to correct object positions 
for proper motion first, and only retrieve the objects whose corrected positions are within 
the search radius.  Setting this flag retrieves objects with uncorrected positions within 
the search radius.

-item B<-old_format>

Print in old mp_get_agasc format:
 
 mp_get_agasc sends to the standard output stream a newline-terminated line
 of space-separated AGASC data for each object found within delta (radius)
 degrees of the position specified by the RA and dec command line
 arguments.  This is the order of the fields on the output line:


                 1  AGASC_ID
                 2  RA
                 3  DEC
                 4  POS_ERR
                 5  POS_CATID
                 6  EPOCH
                 7  PM_RA
                 8  PM_DEC
                 9  PM_CATID
                10  PLX
                11  PLX_ERR
                12  PLX_CATID
                13  MAG_ACA
                14  MAG_ACA_ERR
                15  CLASS
                16  MAG
                17  MAG_ERR
                18  MAG_BAND
                19  MAG_CATID
                20  COLOR1
                21  COLOR1_ERR
                22  COLOR1_CATID
                23  COLOR2
                24  COLOR2_ERR
                25  COLOR2_CATID
                26  RSV1
                27  RSV2
                28  RSV3
                29  VAR
                30  VAR_CATID
                31  ASPQ1
                32  ASPQ2
                33  ASPQ3
                34  ACQQ1
                35  ACQQ2
                36  ACQQ3
                37  ACQQ4
                38  ACQQ5
                39  ACQQ6
                40  XREF_ID1
                41  XREF_ID2
                42  XREF_ID3
                43  XREF_ID4
                44  XREF_ID5
                45  RSV4
                46  RSV5
                47  RSV6


=head1 DESCRIPTION

B<mp_get_agasc.pl> uses Ska::AGASC to retrieve all of the objects from the AGASC that are 
within the specified search radius of the specified star position.  Positions are corrected
for proper motion based on the input date, or the current time is used for correction.


=head1 AUTHOR

Jean Connelly, E<lt>jeanconn@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Smithsonian Astrophysical Observatory

This script is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.
