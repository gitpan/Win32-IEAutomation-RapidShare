use ExtUtils::MakeMaker;

if($^O !~ /MSWin32/ ){
	print "OS unsupported\n";
	print "No support for OS\n";
	exit;
}

WriteMakefile(
    NAME              => 'Win32::IEAutomation::RapidShare',
    VERSION_FROM      => 'lib/Win32/IEAutomation/RapidShare.pm', # finds $VERSION
    PREREQ_PM         => {
    	Win32::IEAutomation	=> 0.5,
    	LWP::UserAgent		=> 5,
    }, 
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Win32/IEAutomation/RapidShare.pm', # retrieve abstract from module
       AUTHOR         => 'Jing Kang <kxj@hotmail.com>') : ()),
);
