# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Ska-AGASC.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok('Ska::AGASC') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# For AGASC ID 1058813608 2020:001 from the Python agasc
# star = agasc.get_star(1058813608, date='2020:001')
# print(star['RA_PMCORR'])
# 77.9706341148
# print(star['DEC_PMCORR'])
# -45.0505974534
# print(star['RA'])
# 77.919199449999994
# print(star['DEC'])
# -45.01851748
my $star_ra_pmcorr = 77.9706341148;
my $star_dec_pmcorr = -45.0505974534;
$cone = Ska::AGASC->new({
      ra => $star_ra_pmcorr,
      dec => $star_dec_pmcorr,
      radius => 1.5,
      datetime => '2020:001:00:00:00.000'});
my $star = $cone->get_star(1058813608);
ok(abs($star->ra() - 77.919199449999994) < 0.00001, "RA catalog match");
ok(abs($star->dec() - -45.01851748) < 0.00001, "Dec catalog match");
ok(abs($star->ra_pmcorrected() - $star_ra_pmcorr) < 0.00001, "RA Corrected match");
ok(abs($star->dec_pmcorrected() - $star_dec_pmcorr) < 0.00001, "Dec Corrected match");
