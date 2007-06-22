#!/usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;
use diagnostics;
use GrabEnv qw(grabenv);

require "lib/Ska/AGASC.pm";

use Ska::Convert qw(date2time);
#use Quat;


use IO::All;
use POSIX;

my $printout = io('check_ska_agasc.txt');


my $agasc_dir = '/data/agasc1p6';
my $req_date = get_curr_time();

my $r2d = 180/3.14159265358979;
my $d2r = 1.0 / $r2d;



#my $req_ra = 0.1;
#my $req_dec = 0.1;
my $radius = 1.3;

for (my $req_ra = 359; $req_ra < 360; $req_ra++){
    for (my $req_dec = -90; $req_dec < 91; $req_dec++){

	$printout->print("\nusing ra:$req_ra and dec:$req_dec\n");

my $agasc_region = Ska::AGASC->new({ 
    ra => $req_ra,
    dec =>  $req_dec,
    radius => $radius, 
    datetime => "$req_date",
    do_not_pm_correct_retrieve => 1,
});



#my %mp_agasc;

if (`which mp_get_agasc` =~ /no mp_get_agasc/) {
    %ENV = grabenv("tcsh", "source /home/ascds/.ascrc -r release");
    if (`which mp_get_agasc` =~ /no mp_get_agasc/) {
	die "Cannot find mp_get_agasc to make plots.  Are you in the CXCDS environment?\n";
    }
}


my $mp_get_agasc = "mp_get_agasc -r $req_ra -d $req_dec -w $radius";
my @stars = `$mp_get_agasc`;

my $seconds_per_day = 86400;
my $days_per_year = 365.25;
my $milliarcsecs_per_degree = 3600 * 1000;

my $r2a = 3600. * 180. / 3.14159265;

my $agasc_start_date = '2000:001:00:00:00.000';

foreach (@stars) {
    s/-/ -/g;
    my @flds = split;

    my ($id, $ra, $dec, $poserr, $pm_ra, $pm_dec, $mag, $magerr, $bv, $class, $aspq)
	= @flds[0..3,6,7,12,13,19,14,30];
    
    

    if ($agasc_region->has_id($id)){
#	$mp_agasc{id} = 1;
    }
    else{
#	use Data::Dumper;
#	print Dumper $agasc_region;
#	$mp_agasc{id} = 0;
	my $dist = sph_dist( $req_ra*$d2r, $req_dec*$d2r, $ra*$d2r, $dec*$d2r)*$r2d;	
	$printout->print("ra:$req_ra\tdec:$req_dec\t$id\tdist=$dist\n");
    }
}

#
### let's correct the agasc star positions for proper motion
##    my $years = (date2time($req_date}) - date2time($agasc_start_date)) / ( $seconds_per_day * $days_per_year);
### ignore those with proper motion of -9999
##$pm_ra = ($pm_ra == -9999) ? 0 : $pm_ra;
##$pm_dec = ($pm_dec == -9999) ? 0 : $pm_dec;
##
### proper motion in milliarcsecs per year
##my $star_ra = $ra + ( $pm_ra * ( $years / $milliarcsecs_per_degree ));
##my $star_dec = $dec + ( $pm_dec * ( $years / $milliarcsecs_per_degree ));
##
###my ($yag, $zag) = Quat::radec2yagzag($star_ra, $star_dec, $q_aca);
###$yag *= $r2a;
###$zag *= $r2a;
##
##$self->{agasc_hash}{$id} = { id=> $id, class => $class,
##			     ra  => $star_ra,  dec => $star_dec,
##			     mag => $mag, bv  => $bv,
##			     magerr => $magerr, poserr  => $poserr,
##			     yag => $yag, zag => $zag, aspq => $aspq } ;
##
#
##}
#
#
#

}
}


sub get_curr_time{
    # if the datetime is undefined for the search, use the time now
    my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = gmtime(time);
    my $year = 1900 + $yearOffset;
    my $date = sprintf("%4d:%03d:%02d:%02d:%02d.000", $year, $dayOfYear, $hour, $minute, $second);
    return $date;
}




##***************************************************************************
sub sph_dist{
##***************************************************************************
# generic formula for spherical distance between two points
# in radians
    my ($a1, $d1, $a2, $d2)= @_;
#    print "$a1 $d1 $a2 $d2 \n";

    return(0.0) if ($a1==$a2 && $d1==$d2);

    return acos( cos($d1)*cos($d2) * cos(($a1-$a2)) +
		 sin($d1)*sin($d2));
}

