package Ska::AGASC;
# Retrieve a hash of stars from the AGASC
# from a defined cone

use strict;
use warnings;
use Data::ParseTable qw( parse_table );
use Math::Trig qw( pi );
use IO::All;
use PDL;
#use Data::Dumper;


my $revision_string = '$Revision$';
my ($revision) = ($revision_string =~ /Revision:\s(\S+)/);

our $VERSION = '1.0';

my $ID_DIST_LIMIT = 1.5;

#my $pi = 4*atan2(1,1);
my $pi = pi;
my $r2a = 180./$pi*3600;
 
my $d2r = $pi/180.;
my $r2d = 1./$d2r;



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

#    print Dumper $lim_ref;

    # load the regions file into an array of hash references
    my $regions_pdl = parse_boundary($par{boundary_file});

    # find the numbers of all the regions that appear to contain a piece of the defined
    # search box
    my @region_numbers = regionsInside( $lim_ref->{rlim}, $lim_ref->{dlim}, $regions_pdl );

#    print Dumper @region_numbers;

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


sub list_ids{
    my $self = shift;
    my @keys = keys %{$self};
    return @keys;
}

sub has_id{
    my $self = shift;
    my $id = shift;
    return (defined $self->{$id});
}

sub get_star{
    my $self = shift;
    my $id = shift;
    my $star = $self->{$id};
    return $star;
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

    my $pdl = pdl(map { parse_boundaryfile_line($_) } @lines);


    return $pdl;
}

sub parse_boundaryfile_line{
    
    my $line = shift;

    chomp $line;
    my @field = split( ' ', $line);
    s/^ *| *$//g for @field;

    my $idx = $field[0];
    my $ra_lo = $field[1];
    my $ra_hi = $field[2];
    my $dec_lo = $field[3];
    my $dec_hi = $field[4];

    if ( $ra_lo > $ra_hi ){
	$ra_lo -= 360;
    }

    if ( $dec_hi < $dec_lo ){
	my $temp = $dec_lo;
	$dec_lo = $dec_hi;
	$dec_hi = $temp;
    }

    return  [ $idx, $ra_lo, $ra_hi, $dec_lo, $dec_hi ];
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
	    my $star_object = Ska::AGASC::Star->new($star, $par->{datetime});
	    $star_object->source_file($file);

	    # sph_dist in radians
	    my $dist = sph_dist( $par->{ra}*$d2r, 
				 $par->{dec}*$d2r,
				 $star_object->ra_pmcorrected()*$d2r,
				 $star_object->dec_pmcorrected()*$d2r)
		       *$r2d;

		

	    if ( $dist < $par->{radius} ){
		$starhash{$star_object->agasc_id()} = $star_object; 
	    }
	}
    }
    return \%starhash;
}

##***************************************************************************
sub sph_dist{
##***************************************************************************
# in radians
    my ($a1, $d1, $a2, $d2)= @_;

    return(0.0) if ($a1==$a2 && $d1==$d2);

    return acos( cos($d1)*cos($d2) * cos(($a1-$a2)) +
		 sin($d1)*sin($d2));
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

    my ($data_rlim, $data_dlim, $regions_pdl) = @_;

# grab the columns of the piddle that interest me

    my $cat_ra_lo = $regions_pdl->slice(1)->reshape(-1);
    my $cat_ra_hi = $regions_pdl->slice(2)->reshape(-1);
    my $cat_dec_lo = $regions_pdl->slice(3)->reshape(-1);
    my $cat_dec_hi = $regions_pdl->slice(4)->reshape(-1);

# find any catalog region that has a boundary contained within the search area
# and any catalog region that completely contains the search area
        
    my $match = which( 
			(
			 ( ($cat_ra_hi >= $data_rlim->[0]) & ($cat_ra_hi <= $data_rlim->[1]) ) 
			 | ( ($cat_ra_lo >= $data_rlim->[0]) & ($cat_ra_lo <= $data_rlim->[1]) ) 
			 | ( ($cat_ra_lo <= $data_rlim->[0]) & ($cat_ra_hi >= $data_rlim->[1]) )
			 )
			&
			(
			 ( ($cat_dec_hi >= $data_dlim->[0]) & ($cat_dec_hi <= $data_dlim->[1]) )
			 | (  ($cat_dec_lo >= $data_dlim->[0]) & ($cat_dec_lo <= $data_dlim->[1]) )
			 | (  ($cat_dec_lo <= $data_dlim->[0]) & ($cat_dec_hi >= $data_dlim->[1]) )
			 )
			);


    # index starts at 0
    $match = $match+1;

    my @regNumbers = list($match);

    return @regNumbers;
}


sub point_in_area{

    my ( $point, $area ) = @_;

#    print Dumper $point;
#    print Dumper $area;

    if ( 
	 ( ($point->{ra} >= $area->{RA_LO}) && ($point->{ra} <= $area->{RA_HI} ) )
	 &&
	 ( ($point->{dec} >= $area->{DEC_LO}) && ($point->{dec} <= $area->{DEC_HI} ) )
	 ){
	return 1;
    }
    
    return 0;

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
#	if ( $lim{rlim}->[$i] < 0){
#	    $lim{rlim}->[$i] += 360;
#	}
    }

    return \%lim;

}


{
package Ska::AGASC::Star;


use strict;
use warnings;
use Ska::Convert qw( date2time );
use Class::MakeMethods::Standard::Hash (
					scalar => [ qw(
						       source_file
						       acqq1
						       acqq2
						       acqq3
						       acqq4
						       acqq5
						       acqq6
						       agasc_id
						       aspq1
						       aspq2
						       aspq3
						       c1_catid
						       c2_catid
						       class
						       color1
						       color1_err
						       color2
						       color2_err
						       dec
						       epoch
						       mag
						       mag_aca
						       mag_aca_err
						       mag_band
						       mag_catid
						       mag_err
						       plx
						       plx_catid
						       plx_err
						       pm_catid
						       pm_dec
						       pm_ra
						       pos_catid
						       pos_err
						       ra
						       rsv1
						       rsv2
						       rsv3
						       rsv4
						       rsv5
						       rsv6
						       var
						       var_catid
						       xref_id1
						       xref_id2
						       xref_id3
						       xref_id4
						       xref_id5
						       )
						    ],
					);

my $agasc_start_date = '2000:001:00:00:00.000';
my $seconds_per_day = 86400;
my $days_per_year = 365.25;
my $milliarcsecs_per_degree = 3600 * 1000;
my $datetime;
my $cat_years;


sub new{
    my $class = shift;
    my $star = shift;
    
    if (not defined $datetime){
	$datetime = shift;
    }

    my %star_info = %{$star}; 
    my $star_ref = \%star_info;

    bless $star_ref, $class;
    return $star_ref;
}


sub ra_pmcorrected{

    my $self = shift;
    return $self->{ra_pmcorrected} if (defined $self->{ra_pmcorrected});

    if (not defined $cat_years){
	$cat_years = (date2time($datetime) - date2time($agasc_start_date)) /
	    ( $seconds_per_day * $days_per_year);
    }

    # ignore those with proper motion of -9999
    my $pm_ra = ($self->pm_ra() == -9999) ? 0 : $self->pm_ra();
    
    # proper motion in milliarcsecs per year
    my $ra_pmcorrected = $self->ra() + ( $pm_ra * ( $cat_years / $milliarcsecs_per_degree ));
				       
    $self->{ra_pmcorrected} = $ra_pmcorrected;
    return $self->{ra_pmcorrected};
    
}

sub dec_pmcorrected{

    my $self = shift;
    return $self->{dec_pmcorrected} if (defined $self->{dec_pmcorrected});

    if (not defined $cat_years){
	$cat_years = (date2time($datetime) - date2time($agasc_start_date)) /
	    ( $seconds_per_day * $days_per_year);
    }
			           
    # ignore those with proper motion of -9999
    my $pm_dec = ($self->pm_dec() == -9999) ? 0 : $self->pm_dec();
    
    # proper motion in milliarcsecs per year
    my $dec_pmcorrected = $self->dec() + ( $pm_dec * ( $cat_years / $milliarcsecs_per_degree ));
				       
    $self->{dec_pmcorrected} = $dec_pmcorrected;
    return $self->{dec_pmcorrected};
    
}

}    


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Ska::AGASC - Perl extension to retrieve stars from the AGASC

=head1 SYNOPSIS

use Ska::AGASC;

my $agasc_region = Ska::AGASC->new({ ra => 30, dec => 40, radius => .05, datetime => '2001:102:12:34:06.000' });
my @star_list = $agasc_region->list_ids();
for my $agasc_id (@star_list){
    my $star = $agasc_region->get_star($agasc_id);
    my $ra = $star->ra();
    my $dec = $star->dec();
    print "id:$agasc_id \tra:$ra \tdec:$dec \n";
}


=head1 DESCRIPTION

   Ska::AGASC retrieves the stars in a region of the agasc and returns a 
   reference to a object that is a hash of those stars.

   It uses AGASC 1.6 by default.  
   

=head1 EXPORT

None by default.

=head1 Ska::AGASC METHODS

=head2 new()
    
    Creates a new instance of the AGASC container object.
    Accepts as its argument an anonymous hash or hashref of attributes which 
    override the defaults.

    Default Parameters
    my %par = (
               ra => 0,
               dec => 0,
               radius => 1.3,
               datetime => get_curr_time(),
               agasc_dir => '/data/agasc1p6/',
               );

   Note: The radius retrieve section calculates the proper motion corrected 
   values of ra and dec (which are stored in the star object as ra_pmcorrected 
   and dec_pmcorrected) and uses those coordinates to determine if the star is 
   actually within the defined retrieve radius.

 
=head2 list_ids()

    Returns an array of the agasc_ids of the star objects within the AGASC region.

=head2 has_id($agasc_id)

    Returns true value if the Ska::AGASC object contains a star with the specified $agasc_id.

=head2 get_star($agasc_id)
    
    Returns the Ska::AGASC::Star object with the specified $agasc_id

=head1 Ska::AGASC::Star Methods

=head2 ra_pmcorrected()

    Gets or sets the proper motion corrected value of the star object's RA.

=head2 dec_pmcorrected()

    Gets or sets the proper motion corrected value of the star object's DEC.

=head2 All other AGASC attributes have standard get/set methods
 Listed here in alphabetical order for convenience

 acqq1
 acqq2
 acqq3
 acqq4
 acqq5
 acqq6
 agasc_id
 aspq1
 aspq2
 aspq3
 c1_catid
 c2_catid
 class
 color1
 color1_err
 color2
 color2_err
 dec
 epoch
 mag
 mag_aca
 mag_aca_err
 mag_band
 mag_catid
 mag_err
 plx
 plx_catid
 plx_err
 pm_catid
 pm_dec
 pm_ra
 pos_catid
 pos_err
 ra
 rsv1
 rsv2
 rsv3
 rsv4
 rsv5
 rsv6
 var
 var_catid
 xref_id1
 xref_id2
 xref_id3
 xref_id4
 xref_id5


=head1 AUTHOR

Jean Connelly, E<lt>jeanconn@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 Smithsonian Astrophysical Observatory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.


=cut
    


