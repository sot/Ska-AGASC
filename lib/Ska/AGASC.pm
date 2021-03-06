package Ska::AGASC;
# Retrieve a hash of stars from the AGASC
# from a defined cone

# used by acq_stat_db/update_acq_stats.pl
# used by starcheck

use strict;
use warnings;
#use Math::Trig qw( pi );
use IO::All;
use PDL;
use Carp;
use Chandra::Time;
use Ska::Convert qw( date2time );
use Shell::GetEnv;
use App::Env;
use Data::Dumper;

my $revision_string = '$Revision$';
my ($revision) = ($revision_string =~ /Revision:\s(\S+)/);

use autouse 'Astro::FITS::CFITSIO::Simple' => qw( rdfits );

our $VERSION = '3.6.0';

our $SMALL_ASCDS_ENV;
our $access_method;

#my $pi = 4*atan2(1,1);
#my $pi = pi;
my $pi = 3.14159265;
my $r2a = 180./$pi*3600;
 

my $d2r = $pi/180.;
my $r2d = 1./$d2r;


# agasc_start_date for calculating proper motion when using mp_get_agasc
# perl retrieval uses fits file "epoch" and does not require this
my $agasc_start_date = '2000:001:00:00:00.000';



sub new{

    
    my $class = shift;
    my $par_ref = shift;
    
    my %par = (
	       ra => 0,
	       dec => 0,
	       radius => 1.3,
	       datetime => get_curr_time(),
	       agasc_dir => '/proj/sot/ska/data/agasc1p6',
	       do_not_pm_correct_retrieve => 0,
	       faint_mag_limit => 20,
	       %{$par_ref},
	       );

    
    # Check and convert, if necessary, input time
    my $test_datetime;
     eval{
 	my $t = Chandra::Time->new($par{datetime});
 	$par{time_object} = $t;
 	$par{datetime} = $t->date();
     };
     if ($@){
 	croak(__PACKAGE__ . " datetime not in YYYY:DOY format or does not convert properly with Chandra::Time \n $@ \n");
     }

 
    if (not defined $access_method){
      set_ascds_env();
    }
    my $self = get_stars( \%par);
    bless $self, $class;

    return $self;
    
}

sub set_ascds_env{
  
    # eval this to catch errors loading ASCDS
    eval{
        local %ENV = ('HOME' => $ENV{HOME},
                      'APP_ENV_ASCDS_STR' => $ENV{APP_ENV_ASCDS_STR});
	 $SMALL_ASCDS_ENV = App::Env->new('ASCDS', {SysFatal => 1});
	 my @ascds_keys = keys %{$SMALL_ASCDS_ENV};
	 for my $ascds_key (@ascds_keys){
	     unless (grep {$_ eq $ascds_key} qw/HOME PATH LD_LIBRARY_PATH MANPATH/){
		 # one argument works as a delete
		 $SMALL_ASCDS_ENV->setenv( $ascds_key );
	     }
	 }
    };
    if ($@){
	print STDERR __PACKAGE__ . " $@";
	$SMALL_ASCDS_ENV = undef;
    }

}

sub get_stars{

    my $par_ref = shift;
    my %par = %{$par_ref};
    
    my $starhash;

    if (defined $SMALL_ASCDS_ENV){
	$access_method = 'mp_get_agasc';
	$starhash = mp_agasc( \%par );
    }
    else{
	$access_method = 'cfitsio';
	$starhash = perl_ska_agasc( \%par );
    }
    return $starhash;
}



sub mp_agasc{

    my $par_ref = shift;
    my %par = %{$par_ref};

    $SMALL_ASCDS_ENV->setenv('ASCDS_AGASC', $par{agasc_dir});
    
    my %starhash;
    my @star_cmd = ('mp_get_agasc', '-r', $par{ra}, '-d', $par{dec}, '-w', $par{radius});
    croak(__PACKAGE__ . " ASCDS environment not defined from launcher \n") unless defined $SMALL_ASCDS_ENV;
    my @stars = $SMALL_ASCDS_ENV->qexec(@star_cmd);

    # let get dtime to correct agasc star positions for proper motion
    my $seconds_per_day = 86400;
    my $days_per_year = 365.25;
    my $years = (date2time($par{datetime}) - date2time($agasc_start_date)) / ( $seconds_per_day * $days_per_year);
    my $milliarcsecs_per_degree = 3600 * 1000;
    
    foreach (@stars) {
	s/-/ -/g;
	my @flds = split;
	
        # AGASC 1.4 and 1.5 are related (one-to-one) with different versions of mp_get_agasc
        # which have different output formats.  Choose the right one based on AGASC version:

        # I'm not sure where the proper motion bits are set in agasc 1.4, so we'll just set
        # them to 0 - Jean

        my ($id, $ra, $dec, $poserr, $pm_ra, $pm_dec, $mag, $magerr, $bv, $class, $aspq)
            = ($par{agasc_dir} =~ /1p4/) ?
            ( @flds[0..3], "0", "0", @flds[7..10], "0") : @flds[0..3,6,7,12,13,19,14,30];
	
	# basic check to see if I got stars with numeric ids
	unless ($id =~ /^\d*$/){
	    croak(__PACKAGE__ . " Did not receive stars from mp_get_agasc\n");
	}

	
	next if $mag > $par{faint_mag_limit};


        # ignore those with proper motion of -9999
	$pm_ra = ($pm_ra == -9999) ? 0 : $pm_ra;
	$pm_dec = ($pm_dec == -9999) ? 0 : $pm_dec;


        # proper motion in milliarcsecs per year
        my $pm_to_degrees = $years / $milliarcsecs_per_degree;
	my $dec_pmcorrected = $dec + $pm_dec * $pm_to_degrees;
        my $ra_scale = cos($dec * $d2r);
	my $ra_pmcorrected = $ra + $pm_ra * $pm_to_degrees / $ra_scale;


	my %star = ( agasc_id => $id,
		     ra => $ra,
		     dec => $dec,
		     ra_pmcorrected => $ra_pmcorrected,
		     dec_pmcorrected => $dec_pmcorrected,
		     pos_err => $poserr,
		     pm_ra => $pm_ra,
		     pm_dec => $pm_dec,
		     mag_aca => $mag,
		     mag_aca_err => $magerr,
		     color1 => $bv,
		     class => $class,
		     aspq1 => $aspq,
		     );

	
	$starhash{ $id } = make_star_object({ star => \%star, par => \%par });
    }


    return \%starhash;
}



sub perl_ska_agasc{ 

    my $par_ref = shift;
    my %par = %{$par_ref};

    # define boundary file and  and neighbor file relative to agasc_dir
    $par{boundary_file} = $par{agasc_dir} . '/tables/boundaryfile';
    $par{neighbor_txt} = $par{agasc_dir} . '/tables/neighbors';

    croak(__PACKAGE__ . " Specified AGASC directory, ", 
	  $par{agasc_dir}, 
	  ", does not exist or does not contain necessary files and directories.\n") 
	unless ( ( -e $par{agasc_dir} ) 
		 and ( -e ($par{agasc_dir} . "/agasc/"))
		 and ( -e ($par{boundary_file}))
		 and ( -e ($par{neighbor_txt})));
    

    # define the ra and dec limits of the search box (we yank a box of stars from the
    # agasc and then step through them to remove those outside the radius)
    my $lim_ref = radeclim( $par{ra}, $par{dec}, $par{radius});

    # load the regions file into an array of hash references
    my $regions_pdl = parse_boundary($par{boundary_file});

    # find the numbers of all the regions that appear to contain a piece of the defined
    # search box
    my @region_numbers = regionsInside( $lim_ref->{rlim}, $lim_ref->{dlim}, $regions_pdl );


    # add all the regions that border the matched regions to our list to deal with small region problems
    my @regions_plus_neighbors = parse_neighbors($par{neighbor_txt}, \@region_numbers);


    # remove duplicates (I realize I could do this without defining 3 arrays, but these are small
    # lists and it seems to be more readable )
    my @uniq_regions = sortnuniq( @regions_plus_neighbors );

    # fits file names start at 1 instead of 0
    my @fits_number = map { $_ + 1 } @uniq_regions;

    # generate a list of fits files to retrieve
    my @fits_list = getFITSSource( $par{agasc_dir} . "/agasc/" , \@fits_number);


    # read all of the fits files and keep the stars that are within the defined radius
    my $starhash = grabFITS( \%par, \@fits_list );
#    print Dumper $starhash;


    return $starhash;

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


sub get_year{
    my $datetime = shift;
    my ($sec, $min, $hr, $doy, $yr) = reverse split ":", $datetime;
    return $yr;
}

sub get_day{
    my $datetime = shift;
    my ($sec, $min, $hr, $doy, $yr) = reverse split ":", $datetime;
    return $doy;
}

sub parse_boundary{

    my $boundary_file = shift;

    my @lines = io($boundary_file)->slurp;

    my $pdl = pdl(map { parse_boundaryfile_line($_) } @lines);

    return $pdl;
}


sub parse_boundaryfile_line{

    # I tried to do this with pure PDL functions, and it took longer than doing it a line at a time
    
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
	# include the region first
	push @regions_plus_neighbors, $region;
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
    
    my $days_per_year = 365.25;
    my $milliarcsecs_per_degree = 3600 * 1000;


    my $dateyear = get_year($par->{datetime});
    my $dateday = get_day($par->{datetime});
#    print "my datetime is $datetime, with year $dateyear and day $dateday  \n";

    my %starhash;

    for my $file (@{$fits_list}){

#	print "loading: $file \n";
	       
	my $pm_string =  "temp_pm_ra=(pm_ra == -9999 || epoch == -9999 ) ? 0 : pm_ra;"
	    . " temp_pm_dec=(pm_dec == -9999 || epoch == -9999 ) ? 0 : pm_dec; "
	    . " pm_multiplier = ( ( ($dateyear - epoch) + ($dateday / $days_per_year) ) / $milliarcsecs_per_degree ); "
	    . " ra_pmcorrected= ra + (temp_pm_ra * pm_multiplier / cos( $par->{dec} * $d2r));"
	    . " dec_pmcorrected = dec + (temp_pm_dec * pm_multiplier );";

       	my $dist_string;
	if ( $par->{do_not_pm_correct_retrieve} ){

	    $dist_string = "dist_from_field_center = $r2d * "
		. " acos( cos( dec * $d2r) * cos( $par->{dec} * $d2r) * cos(( ra-$par->{ra} ) * $d2r) "
		. " + sin( dec * $d2r ) * sin( $par->{dec} * $d2r )) ";
#	    
#	    $dist_string = "dist_from_field_center = $r2d*2*"
#		. "arcsin(sqrt( "
#		. " (sin(((ra*$d2r) - ($par->{ra}*$d2r))/2)**2)" 
#		. " + cos(($par->{ra}*$d2r))*cos((ra*$d2r))*((sin( (($par->{dec}*$d2r) - (dec*$d2r))/2))**2)"
#		. "))";
#	    $dist_string = "dist_from_field_center = "
#		. "arccos( (sin(ra*$d2r)*sin($par->{ra}*$d2r)))";
#		. "(cos(ra*$d2r)*cos($par->{ra}*$d2r)*cos((dec*$d2r)-($par->{dec}*$d2r))"
#		. "))";;

	}
	else{

	    $dist_string = "dist_from_field_center = $r2d * "
		. " acos( cos( dec_pmcorrected * $d2r) * cos( $par->{dec} * $d2r) * cos(( ra_pmcorrected-$par->{ra} ) * $d2r) "
		. " + sin( dec_pmcorrected * $d2r ) * sin( $par->{dec} * $d2r )) ";

# Well, I though the haversine would be better, but it seems to be twice the distance I expect (maybe the
# 2 is a typo

#	    $dist_string = "dist_from_field_ center = $r2d*2*"
#		. "arcsin(sqrt( "
#		. " (sin(((ra_pmcorrected*$d2r) - ($par->{ra}*$d2r))/2)**2)" 
#		. " + cos(($par->{ra}*$d2r))*cos((ra_pmcorrected*$d2r))*((sin( (($par->{dec}*$d2r) - (dec_pmcorrected*$d2r))/2))**2)"
#		. "))";
#	    $dist_string = "dist_from_field_center = $r2d * "
#		. "arccos( (sin(ra*$d2r)*sin($par->{ra}*$d2r))"
#		. "+ (cos(ra*$d2r)*cos($par->{ra}*$d2r)*cos((dec*$d2r)-($par->{dec}*$d2r))"
#		. "))";;


	}


	my $filter;
	my $radial_filter = " dist_from_field_center <= $par->{radius} ";
#	my $radial_filter = '';

	if (defined $par->{faint_mag_limit}){
	    $filter  = "mag_aca < " . $par->{faint_mag_limit} . " &&  $radial_filter " ;
	} 
	else{
	    $filter = $radial_filter;
	}


	my %fits_hash = rdfits("$file\[col $pm_string $dist_string;*\]", { rfilter => "$filter"});
#	my %fits_hash = rdfits("$file\[col $pm_string $dist_string;*\]");

	my $count = nelem($fits_hash{agasc_id});
#	print "count is $count \n";

	for my $i (0 .. $count-1){
	    my %star;
	    for my $hash_key (keys %fits_hash){
		$star{$hash_key} = $fits_hash{$hash_key}->at($i);
	    }
	    my $star_object = make_star_object({ star => \%star, par => $par, file => $file });
	    $starhash{$star_object->agasc_id()} = $star_object;
	}
	
    }



    return \%starhash;
}



sub make_star_object{

    my $arg_in = shift;
    my $star = $arg_in->{star};
    my $par = $arg_in->{par};

    my $star_object = Ska::AGASC::Star->new($star, $par->{datetime});
    
    if (defined $arg_in->{file}){
	my $file = $arg_in->{file};
	$star_object->source_file($file);
    }

    return $star_object;
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
	my @filelist = glob("$agasc_dir/*/$searchnum.[Ff][Ii][Tt]");
	
	push @fits, @filelist;
    }
    return @fits;
}


sub regionsInside{

    my ($data_rlim, $data_dlim, $regions_pdl) = @_;

# grab the columns of the piddle hash that interest me

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



    my @regNumbers = list($match);

    return @regNumbers;
}




sub radeclim{
# ugly hack copied almost directly from matlab code

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
1;
#
#{
package Ska::AGASC::Star;


use strict;
use warnings;
use Class::MakeMethods::Standard::Hash (
					scalar => [ qw(
						       source_file
						       pm_multiplier
						       dist_from_field_center
						       ra_pmcorrected
						       dec_pmcorrected
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


my $datetime;


sub new{
    my $class = shift;
    my $star = shift;

    $datetime = shift unless defined $datetime;
    
    my $star_ref = \%{$star};

    bless $star_ref, $class;
    return $star_ref;
}
    




1;
__END__
# Below is stub documentation for your module. You had better edit it!

=head1 NAME

Ska::AGASC - Perl extension to retrieve stars from the AGASC

=head1 SYNOPSIS

use Ska::AGASC;

 my $agasc_region = Ska::AGASC->new({ 
                                     ra => 30, 
                                     dec => 40, 
                                     radius => .05, 
                                     datetime => '2001:102:12:34:06.000' 
                                     });

 my @star_list = $agasc_region->list_ids();
 for my $agasc_id (@star_list){
     my $star = $agasc_region->get_star($agasc_id);
     my $ra = $star->ra();
     my $dec = $star->dec();
     print "id:$agasc_id \tra:$ra \tdec:$dec \n";
 }


=head1 DESCRIPTION

Ska::AGASC retrieves the stars in a region of the agasc and returns a
reference to an object that is a hash of those stars.

It uses AGASC 1.6 by default.  

=head1 EXPORT

None by default.

=head1 Ska::AGASC METHODS

Methods for Ska::AGASC object

=over 4

=item * new()

Creates a new instance of the AGASC container object. Accepts as its
argument an anonymous hash or hashref of creation attributes which override the
defaults.

    Default Parameters
    my %par = (
               ra => 0,
               dec => 0,
               radius => 1.3,
               datetime => (current time),
               agasc_dir => '/data/agasc1p6/',
               faint_mag_limit => 20,
               do_not_pm_correct_retrieve => 0,
              );


ra, dec, and radius are expected as degrees.

By default, datetime is set to the current time.  The datetime
parameter may be set to a date in any format recognized by
Chandra::Time .

agasc_dir specifies the parent directory location of the agasc (i.e. a
directory that contains the directories 'agasc' and 'tables').

mag_limit specifies the faint limit.  Stars dimmer than the limit
are not retrieve from the agasc.

Note: The radius retrieve section calculates the proper motion
corrected values of ra and dec (which are stored in the star object as
ra_pmcorrected and dec_pmcorrected) and uses those coordinates to
determine if the star is actually within the defined retrieve radius.

do_not_pm_correct_retrieve is a boolean option.  If set to a value of
1, stars are discarded if their uncorrxected positions are outside the
requested radius.  The default is to correct for proper motion first.


Note: At the time of this release, use of the cfitsio method is
incompatible with the cfitsio library that is part of the ASCDS release.
Thus, if the environment variable LD_LIBRARY_PATH has been set to
include DS libs, Ska::AGASC will likely segfault.  Unset
LD_LIBRARY_PATH if necessary.


=item * list_ids()

Returns an array of the agasc_ids of the star objects within the AGASC region.

=item * has_id($agasc_id)

Returns true value if the Ska::AGASC object contains a star with the specified $agasc_id.

=item * get_star($agasc_id)

Returns the Ska::AGASC::Star object with the specified $agasc_id

=back

=head1 Ska::AGASC::Star Methods

Methods for the individual Star objects contained in the Ska::AGASC object

=over 4

=item * ra_pmcorrected()

Gets or sets the proper motion corrected value of the star object's RA.

=item * dec_pmcorrected()

Gets or sets the proper motion corrected value of the star object's DEC.

=item * source_file()

Gets or sets the name of the fits file in the AGASC that provided the data for the star

=item * dist_from_field_center()

Gets or sets the distance the star is from the center of the specified search radius.  
In degrees.

=item * pm_multiplier()

Gets or sets the proper motion multiplier .. years / milliarcsecs_per_degree to convert
pm_ra and pm_dec to degrees for the specified time

=item * All other AGASC attributes have standard get/set methods
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

=back

=head1 AUTHOR

Jean Connelly, E<lt>jeanconn@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 Smithsonian Astrophysical Observatory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.


=cut
