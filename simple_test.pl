#!/usr/bin/env /proj/sot/ska/bin/perlska

use Ska::AGASC;
use strict;
use warnings;
use Getopt::Long;

my %par;

GetOptions( \%par,
            'date=s',
	    'ra=s',
            'dec=s',
	    'radius=s',
           ) ||
    exit( 1 );

my $agasc_region = Ska::AGASC->new({ 
    agasc_dir => '/data.fido/storage/standalone/agasc1p6/',
    ra => $par{ra}, 
    dec => $par{dec}, 
    radius => $par{radius}, 
    datetime => $par{date},
});

my @star_list = $agasc_region->list_ids();
for my $agasc_id (@star_list){
    my $star = $agasc_region->get_star($agasc_id);
    my $ra = $star->ra_pmcorrected();
    my $dec = $star->dec_pmcorrected();
	my $pm_ra = $star->pm_ra();
	my $pm_dec = $star->pm_dec();
#    my $file = $star->source_file();
    print "id:$agasc_id \tra:$ra \tdec:$dec \tpm_ra:$pm_ra \tpm_dec:$pm_dec\n";
}


