use strict;
use Test;
use Win32::IEAutomation::RapidShare;

BEGIN { plan tests => 4 }

my $ie = Win32::IEAutomation::RapidShare->new(
	visible 	 => 1,
	debug   	 => 1,
	loopServer   => 'yes',
	stopIfBroken => 'yes'
);

my $url = 'http://rapidshare.com/users/ISWUF5';

my $num = $ie->add_rslinks( url => $url );
print "  -->  $num\n" ;
ok($num > 1);

$num = $ie->check_rslinks();
print "  -->  $num\n" ;
ok($num == 0);

my @uuu = qw(
http://rapidshare.com/files/193694312/Harvard_Business_Review_February_2009.rar
http://rapidshare.com/files/193694312/Harvard_Business_Review_February_2009.rar
http://rapidshare.com/files/193694312/Harvard_Business_Review_February_2009.rar
http://rapidshare.com/files/193694312/Harvard_Business_Review_February_2009.rar
http://rapidshare.com/files/193694312/Harvard_Business_Review_February_2009.rar
);

$num = $ie->add_rslinks( array => \@uuu );
print "  -->  $num\n" ;
ok($num == 50);

$num = $ie->add_rslinks( file => "rsList.txt");
print "  -->  $num\n" ;

$ie->closeIE();
ok($num == 55);
