package Ska::AGASC;
# Retrieve a hash of stars from the AGASC
# from a defined cone

use strict;
use warnings;
use Data::ParseTable qw( parse_table );
use Math::Trig qw( great_circle_distance );
use Data::Dumper;
use Ska::Convert qw( date2time );
use IO::All;
use Quat;

my $revision_string = '$Revision$';
my ($revision) = ($revision_string =~ /Revision:\s(\S+)/);

my $ID_DIST_LIMIT = 1.5;

my $pi = 4*atan2(1,1);
my $r2a = 180./$pi*3600;
 
my $d2r = $pi/180.;
my $r2d = 1./$d2r;

my $agasc_start_date = '2000:001:00:00:00.000';

sub new{

    my $class = shift;
    my $par_ref = shift;

    my $SKA = $ENV{SKA} || '/proj/sot/ska';

    my %par = (
	       ra => 0,
	       dec => 0,
	       radius => 1.3,
	       datetime => get_curr_time(),
	       agasc_dir => '/data/agasc1p6/',
	       );
    $par{boundary_file} = $par{agasc_dir} . 'tables/boundaryfile';
    $par{neighbor_txt} = $par{agasc_dir} . 'tables/neighbors';
    

    # Override Defaults as needed from passed parameter hash
    while (my ($key,$value) = each %{$par_ref}) {
        $par{$key} = $value;
    }
    
    my $agasc_dir = $par{agasc_dir} . 'agasc';

    # define the ra and dec limits of the search box (we yank a box of stars from the
    # agasc and then step through them to remove those outside the radius)
    my $lim_ref = radeclim( $par{ra}, $par{dec}, $par{radius});

    # load the regions file into an array of hash references
    my $regions_mat = parse_boundary($par{boundary_file});

    # find the numbers of all the regions that appear to contain a piece of the defined
    # search box
    my @region_numbers = regionsInside( $lim_ref->{rlim}, $lim_ref->{dlim}, $regions_mat );

    # add all the regions that border the matched regions to deal with small region problems
    my @regions_plus_neighbors = parse_neighbors($par{neighbor_txt}, \@region_numbers);

    # remove duplicates (I realize I could do this without defining 3 arrays, but these are small
    # lists and it seems to be more readable )
    my @uniq_regions = sortnuniq( @regions_plus_neighbors );

    # generate a list of fits files to retrieve
    my @fits_list = getFITSSource( $agasc_dir, \@uniq_regions);
    
    # read all of the fits files and keep the stars that are within the defined radius
    my $starhash = grabFITS( \%par, \@fits_list );

    my $self = $starhash;

    bless $self, $class;
    return $self;
}

sub get_curr_time{

    # if the datetime is undefined for the search, use the time now
    my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = gmtime(time);
    my $year = 1900 + $yearOffset;
    my $date = sprintf("%4d:%03d:%02d:%02d:%02d.000", $year, $dayOfYear, $hour, $minute, $second);
    return $date;
}

sub parse_boundary{

    my $boundary_file = shift;

    my @lines = io($boundary_file)->slurp;

    my @regions;

    for my $line (@lines){

	chomp $line;
	my @field = split( ' ', $line);
        s/^ *| *$//g for @field;

	my %region = ( RA_LO => $field[1],
		       RA_HI => $field[2],
		       DEC_LO => $field[3],
		       DEC_HI => $field[4],
		       );
	push @regions, \%region;
    }
    return \@regions;
}
	    
	



sub parse_neighbors{

    my $neighbor_file = shift;
    my $regionnum_aref = shift;

    my @lines = io($neighbor_file)->slurp;

    my @regions_plus_neighbors;

    for my $region (@{$regionnum_aref}){
	# find lines in the neighbor file that begin with the region specified
	my @match = grep /^$region\s/, @lines;
	for my $line (@match){
	    chomp $line;
	    # dice the line and store the region numbers to the array
	    my @nlist = split( ' ', $line);
	    push @regions_plus_neighbors, @nlist;
	}
    }

    return @regions_plus_neighbors;
}
    


sub grabFITS{

    my $par = shift;
    my $fits_list = shift;

    my %starhash;

    for my $file (@{$fits_list}){
	my $stars = parse_table( $file );
	for my $star (@{$stars}){
	    pm_correct( $star, $par );
	    # great_circle_distance from Math::Trig defaults to radians
	    my $dist = great_circle_distance( $par->{ra}*$d2r, 
				              $par->{dec}*$d2r, 
				              $star->{ra_pmcorrected}*$d2r, 
				              $star->{dec_pmcorrected}*$d2r)
					      *$r2d;


	    if ( $dist < $par->{radius} ){
		$starhash{$star->{agasc_id}} = $star;
		
	    }
	}
    }
    return \%starhash;
}


sub pm_correct{

    my $star = shift;
    my $par = shift;

    my $seconds_per_day = 86400;
    my $days_per_year = 365.25;
    my $years = (date2time($par->{datetime}) - date2time($agasc_start_date)) /
	( $seconds_per_day * $days_per_year);
    
    # ignore those with proper motion of -9999
    my $pm_ra = ($star->{pm_ra} == -9999) ? 0 : $star->{pm_ra};
    my $pm_dec = ($star->{pm_dec} == -9999) ? 0 : $star->{pm_dec};
    
    my $milliarcsecs_per_degree = 3600 * 1000;
    # proper motion in milliarcsecs per year
    $star->{ra_pmcorrected} = $star->{ra} + ( $pm_ra * ( $years / $milliarcsecs_per_degree ));
    $star->{dec_pmcorrected} = $star->{dec} + ( $pm_dec * ( $years / $milliarcsecs_per_degree ));
    
}




sub sortnuniq{
    my @array = @_;
    
    my %hash = map { $_ => 1 } @array;

    my @array2 = sort keys %hash;

    return @array2;
}

sub getFITSSource{
    
    my $agasc_dir = shift;
    my $nfile_ref = shift;
    my @fits;

    for my $num (@{$nfile_ref}){
	my $searchnum = sprintf( "%04d", $num);
	my @filelist = glob("$agasc_dir/*/$searchnum.fit");
	
	push @fits, @filelist;
    }
    return @fits;
}


sub regionsInside{
# ugly hack copied from matlab (now in sad "for" loop )

    my ($rlim, $dlim, $regions) = @_;
    
    my @rliml = @{$rlim};
    my @rlimh = @{$rlim};
    
    if ($rlim->[0] > $rlim->[1]){
	$rliml[0] = $rlim->[0] - 360;
	$rlimh[1] = $rlim->[1] + 360;
    }

    my @regNumbers;

    for my $index (0 .. scalar(@{$regions})-1){

	# step through the regions in ra and dec and a define a true status bit if there
	# is a hit on either

	my $idxrlo = 0;
	my $idxrhi = 0;
	my $idxdlo = 0;
	my $idxdhi = 0;
	my $spanra = 0;
	my $spandec = 0;


	if ( ($rliml[0] <= $regions->[$index]->{RA_LO} )
	     && ( $regions->[$index]->{RA_LO} <= $rliml[1] ) ){
	    $idxrlo = 1;
	}
	if ( ($rlimh[0] <= $regions->[$index]->{RA_HI} )
	     && ( $regions->[$index]->{RA_HI} <= $rlimh[1] ) ){
	    $idxrhi = 1;
	}
	if ( ($dlim->[0] <= $regions->[$index]->{DEC_LO} )
	     && ( $regions->[$index]->{DEC_LO} <= $dlim->[1] ) ){
	    $idxdlo = 1;
	}
	if ( ($dlim->[0] <= $regions->[$index]->{DEC_HI} )
	     && ( $regions->[$index]->{DEC_HI} <= $dlim->[1] ) ){
	    $idxdhi = 1;
	}
	if ( ( $regions->[$index]->{RA_LO} <= $rliml[0] )
	     && ( $regions->[$index]->{RA_HI} >= $rliml[1]) ){
	    $spanra = 1;
	}
	if ( ( $regions->[$index]->{DEC_LO} <= $dlim->[0] )
	     && ( $regions->[$index]->{DEC_HI} >= $dlim->[1]) ){
	    $spandec = 1;
	}

	if ( ( $idxrlo || $idxrhi || $spanra ) && ( $idxdlo || $idxdhi || $spandec ) ){
	    # if there is a hit on both ra and dec, push the region to the list of matching ones
	    # add one because the indexing starts at 1
	    push @regNumbers, $index + 1;
	}
    }
    
    return @regNumbers;
}


sub radeclim{
# ugly hack copied from matlab code

    my ($ra, $dec, $radius) = @_;
    my %lim;

    if( ($dec + $radius) > 90){   
	$lim{rlim} = [ 0,360];
	$lim{dlim} = [($dec - $radius), 90]; 
	return \%lim;
    }   
    else{
	if ( ($dec - $radius) < -90 ){   
	    $lim{rlim} = [ 0, 360];
	    $lim{dlim} = [ (-90), ($dec+$radius)];
	    return \%lim;
	}
    }

#%For the final case, find the min/max RA value
    $lim{dlim} = [ ($dec - $radius), ($dec + $radius) ];

    my $del_ra = atan2( sin($radius*$d2r) , sqrt(cos($dec*$d2r)**2 - sin($radius*$d2r)**2) ) *$r2d;

    $lim{rlim} = [ ($ra - $del_ra), ($ra + $del_ra) ];

    
    for my $i ( 0 .. 1 ){
	if ( $lim{rlim}->[$i] > 360 ){
	    $lim{rlim}->[$i] -= 360;
	}
	if ( $lim{rlim}->[$i] < 0){
	    $lim{rlim}->[$i] += 360;
	}
    }

    return \%lim;

}

# Let's keep this section if  we decide to read directly from the REGIONS.TBL

#my $regions_tbl = parse_table('REGIONS.TBL');
#
#my @mat;
#


#use Ska::Convert qw( hms2dec );
#
#
#
#for my $region (@{$regions_tbl}){
#    my ($ra_lo, $dec_lo) = hms2dec( $region->{ra_h_low}, $region->{ra_m_low}, $region->{ra_s_low}, $region->{decsi_lo}.$region->{dec_d_lo}, $region->{dec_m_lo}, 0);
#    my ($ra_hi, $dec_hi) = hms2dec( $region->{ra_h_hi}, $region->{ra_m_hi}, $region->{ra_s_hi}, $region->{decsi_hi}.$region->{dec_d_hi}, $region->{dec_m_hi}, 0);
#    $ra_hi = ($ra_hi >= 360) ? $ra_hi - 360 : $ra_hi;
#    my %point = ( 
#		  RA_LO => $ra_lo,
#		  DEC_LO => $dec_lo,
#		  RA_HI => $ra_hi,
#		  DEC_HI => $dec_hi,
#		  );
#    push @mat, \%point,
#}
#
#
#use Data::Dumper;
#for my $index (0 .. scalar(@{$regions_tbl})-1){
#    unless ( ($mat[$index]->{RA_LO} == $regions_mat->[$index]->{RA_LO})
#	  && ($mat[$index]->{RA_HI} == $regions_mat->[$index]->{RA_HI})
#	  && ($mat[$index]->{DEC_LO} == $regions_mat->[$index]->{DEC_LO})
#	  && ($mat[$index]->{DEC_HI} == $regions_mat->[$index]->{DEC_HI})
#	     ){
#	print Dumper $mat[$index];
#	print Dumper $regions_mat->[$index];
#    }
#}
#
#print Dumper @mat;
#





1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Ska::AGASC - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Ska::AGASC;
  my $agasc_region = Ska::AGASC->new({ ra => 30, dec => 40, radius => 1.3, datetime => '2001:102:12:34:06.000' });

=head1 DESCRIPTION

   Ska::AGASC retrieves the stars in a region of the agasc and returns a reference to a object that is a hash of those stars.
   It uses AGASC 1.6 by default.  

=head2 EXPORT

None by default.

    

=head1 AUTHOR

Jean Connelly, E<lt>jeanconn@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jean Connelly

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.


=cut
