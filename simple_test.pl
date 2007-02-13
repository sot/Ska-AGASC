#!/usr/bin/env /proj/sot/ska/bin/perlska

#use Ska::AGASC;
require '/proj/gads6/jeanproj/Ska-AGASC/lib/Ska/AGASC.pm';
use strict;
use warnings;
use Getopt::Long;

my %par;

GetOptions( \%par,
            'date=s',
	    'ra|r=s',
            'dec|d=s',
	    'radius|w=s',
	    'mag_limit=s',
	    'do_not_pm_correct_retrieve|nc!',
           ) ||
    exit( 1 );


use Data::Dumper;
#print Dumper %par;

my $agasc_region = Ska::AGASC->new(\%par);
#    agasc_dir => '/data.fido/storage/standalone/agasc1p6/',

my @star_list = $agasc_region->list_ids();
for my $agasc_id (@star_list){
    my $star = $agasc_region->get_star($agasc_id);
    my $ra = $star->ra_pmcorrected();
    my $dec = $star->dec_pmcorrected();
    my $pm_ra = $star->pm_ra();
    my $pm_dec = $star->pm_dec();
    my $mag = $star->mag_aca();
    my $dist = $star->dist_from_field_center();
#    my $file = $star->source_file();
    printf("id: %s \t ra:%3.2f \t dec:%3.2f \t pm_ra:%s \t pm_dec:%s \t dist:%3.7f \n", $agasc_id, $ra, $dec, $pm_ra, $pm_dec, $dist);
}


