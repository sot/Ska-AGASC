use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      NAME              => 'Ska::AGASC',
	      VERSION_FROM      => 'lib/Ska/AGASC.pm',
	      PREREQ_PM         => { IO::All => undef,
		Astro::FITS::CFITSIO::Simple => undef,
		Math::Trig => undef,
		Ska::Convert => undef,
		Class::MakeMethods::Standard::Hash => undef,
	    }, # e.g., Module::Name => 1.1
	      ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
	       (ABSTRACT_FROM  => 'lib/Ska/AGASC.pm', # retrieve abstract from module
		AUTHOR         => 'Jean Connelly <jeanconn@localdomain>') : ()),
	      );
