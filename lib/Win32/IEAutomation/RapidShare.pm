package Win32::IEAutomation::RapidShare;

#h2xs -XA -O -n Win32::IEAutomation::RapidShare

use strict;
use warnings;
use vars '@ISA';
use Win32::IEAutomation;

our @ISA = qw(Win32::IEAutomation);
our $VERSION = '0.03';

my $error1 = q(Error);
my $rsMsg0 = q(The file could not be found);
my $rsMsg1 = q(is already downloading a file);
my $rsMsg2 = q(You have reached the download limit for free-users);
my $rsMsg3 = q(You are not a Premium User and have to wait);
my $rsMsg4 = q(Advanced download settings);	
my $rsMsg5 = q(This file is suspected to contain illegal content);	

my @dlServer;

sub new {
	my ($unknown, %usr_parms)= @_;
	my $class = ref($unknown) ? ref($unknown) : $unknown;

	my %obj_parms ;
	while(my($k, $v) = each %usr_parms){
		$obj_parms{lc($k)} = $v;
	}

    my $self = $class->SUPER::new(
    	visible => $obj_parms{'visible'} ? $obj_parms{'visible'} : 0
    );

	$self->{debug}		  = $obj_parms{debug}		|| undef;
	$self->{loopserver}	  = $obj_parms{loopserver}	|| undef;
	$self->{dltool}		  = $obj_parms{dltool}		|| 'lwp-download ';
	$self->{links}		  = $obj_parms{links}		|| [];
	$self->{stopifbroken} = $obj_parms{stopifbroken}|| undef;

	$self->{preferserver} = $obj_parms{preferserver}|| undef;

	$self->{starttime}    = $obj_parms{starttime}	|| "00:00:00";
	$self->{stoptime}     = $obj_parms{stoptime}	|| "23:59:59";

	$self->{taskname}     = $obj_parms{taskname}	|| 'rapidshare';

	undef $self->{loopserver} if($self->{preferserver});

	_removeDupLink($self->{links});	

    bless $self, $class;
	$self;
}

## -------------------------------------------------------------------
sub modifyTime(){		#add or minus some hour
	my $time 	= shift;
	my $offset	= shift;
	
	my @tm = split /:/, $time;
	$tm[0] =~ /0*(\d+)/;
	$tm[0] = $1;

	$tm[0] = $tm[0] - $offset;
	$tm[0] = $tm[0] >= 0 ? $tm[0] : $tm[0]+24;
	
	$tm[0] = sprintf("%02d", $tm[0]);
	join(":", @tm);
}

sub isInScheduledTime(){#judge if now() in the time range
	my $st = shift;		#start time
	my $et = shift;		#  end time

	my $nw = _getTime();
	
	my @tm = split /:/, $st;
	$tm[0] =~ /0*(\d+)/;
	$tm[0] = $1;		#get start hour, set start hour to 00

	$st = &modifyTime($st, $tm[0]);
	$et = &modifyTime($et, $tm[0]);
	$nw = &modifyTime($nw, $tm[0]);

	return $nw ge $st && $nw le $et ? "ok" : undef;
}

sub add_rslinks {
    my $self = shift;
    my $from = shift;

	if($from =~ /array/i ){
		my $aref = shift;
		#add array together
		@{$self->{links}} = (@{$self->{links}}, @{$aref});

	}elsif($from =~ /file/i ){		#read links from txt
		my $file = shift;
		die "  Error: specified file $file not found\n" unless -e $file;
		
		open(LNK, $file);
		while( my $line = <LNK> ){
			chomp $line;
			next if($line !~ /^http/i	   );
			next if($line !~ /rapidshare/i );
			push @{$self->{links}}, $line;
		}
		close LNK;
	
	}elsif($from =~ /url/i ){ #sample http://rapidshare.com/users/ISWUF5
	
		$self->gotoURL( shift );
	
		#parse links from html
		my @links = $self->Content() =~ /.*?href=\"(http:\/\/.*?)\".*?/g;

		map {push @{$self->{links}}, $_ if ($_ =~ /\/files\// )} @links ;
	}

	_removeDupLink($self->{links});
	print "  " . scalar @{$self->{links}} . " links added\n" if($self->{debug});

	return scalar @{$self->{links}};
}

sub check_rslinks {
    my $self = shift;

	$self->gotoURL( 'http://rapidshare.com/checkfiles.html' );

	#add to text area
	$self->getTextArea('name:', "urls")->SetValue( join "\n", @{$self->{links}} );

	sleep 1;
	$self->getButton('value:', "Check URLs")->Click;
	sleep 1;

	my $rsPage = $self->Content();
	# remove the sensitive string from javascript 
	$rsPage =~ s/st = \"File inexistent\";//i ;

	my @brokenURL = $rsPage =~ /.*?File inexistent.*?(http:\/\/.*?)\<\/div\>/gsi;

	if(scalar @brokenURL > 0){
		print "  Broken links:\n    ";
		print join "\n    ", @brokenURL;
		print "\n";	
	}
	
	#you don't want to download files that cannot be unzipped.
	die "  Some links are broken. To aviod downloading partial file, exit now\n" 
	if($self->{stopifbroken} && scalar @brokenURL > 0);
	
	return scalar @brokenURL;
}

sub _removeDupLink(){
    my $refl = shift;
	return if( scalar @$refl < 1);	

	my %ttt;
	foreach( @$refl ){
		my $url = $_;
		my @tmp = split /\//, $url;
		my $filename = $tmp[$#tmp];

		$ttt{$filename} = $url;
	}
	@$refl = ();

	#sort file name
	foreach( sort keys %ttt ){
		push @$refl, $ttt{$_};
	}
}

sub downloadrs(){
    my $ie = shift;

	my $loop=0;

	#save the list for further reference
	my $taskFile = $ie->{taskname} . '.rs.txt';
	$taskFile = $ie->{taskname} .'.'. time . '.rs.txt' if(-e $taskFile);

	open (RSTASK, ">$taskFile");
	map {print RSTASK "$_\n"} @{$ie->{links}};
	close RSTASK;

	foreach(@{$ie->{links}}){
		my $url = $_;

		my @tmp = split /\//, $url;
		my $filename = $tmp[$#tmp];

		print "\n  processing $filename...\n";
		next if(-e $filename);

		my $retry = 0;
		while(1){

			#check if current time in the scheduled time range
			if( ! &isInScheduledTime($ie->{starttime}, $ie->{stoptime}) ){
				print "\r  current time isn't in scheduled time range. ".$ie->{starttime}." ".$ie->{stoptime} if($ie->{debug});
				`hostname`;
				sleep(1);
				print "\r" .' 'x45 if($ie->{debug});
				_delay(180);
				next;
			}

			$ie->gotoURL($url);

			# This file is suspected to contain illegal content
			if( $ie->PageText() =~ /$rsMsg5/i ){
				print "  Error: This file is suspected to contain illegal content\n";
				last;
			}

			eval{
				$ie->getButton('value:', "Free user")->Click;
				sleep 1;
			};
			if($@){	#page isn't loaded, internet might not be available, wait
				print "\r  Free User button isn't found. Check the INTERNET access." if($ie->{debug});
				`hostname`;
				sleep(2);
				print "\r" .' 'x75 if($ie->{debug});

				last if($retry > 10);	#retry 10 times
				_delay(180);
				$retry++;
				next;
			}

			#file doesn't exist
			if($ie->PageText() =~ /$error1/ && $ie->PageText() =~ /$rsMsg0/i ){
				print "  specified file doesn't exist\n" if($ie->{debug});
				last;
			}

			#no simultaneous download
			if($ie->PageText() =~ /$error1/ && $ie->PageText() =~ /$rsMsg1/i ){
				print "  downloading one file at a time\n" if($ie->{debug});
				_delay(300);
				next;
			}

			#download limit checking
			if($ie->PageText() =~ /$error1/ && $ie->PageText() =~ /$rsMsg2/i ){
				$ie->PageText() =~ /Or try again in about (\d+) (.*)\./ ;
				print "\r  free user has download limits,        : $1 $2" if($ie->{debug});
				my $min = $1;

				sleep 2;
				if( $min > 3){
					_delay( 60 * ($min-2) - 2);
				}else{
					_delay( 60 );
				}
				next;
			}

			#wait 50 sec
			if( $ie->PageText() =~ /$rsMsg3/i ){
				$ie->PageText() =~ /Still (\d+) .*/ ;
				print "\r  free user has to wait: $1 seconds". ' 'x37 . "\n" if($ie->{debug});
				#$ie->gotoURL('javascript:jkang(c=0)');
				_delay($1+2);
			}

			#start downloading
			if( $ie->PageText() =~ /$rsMsg4/i ){

				$ie->Content()  =~ /action=\"(.*?)\"/;
				my $downloadUrl = $1;

				if(! $downloadUrl){
					print "\n  Error: no download url found!";
					next;
				}

				#try advanced download server, loop all server to figure out fast one
				if( $ie->{loopserver} ){
					#get all alternative links
					my %links = $ie->Content() =~ /document\.dlf\.action=\\'(.*?)\\';\" \/\> (.*?)\<br/g;

					my %svrUrl;
					print "\n";
					while( my ($u, $n) =  each %links){
						printf "  %20s    %s\n", $n , $u if($ie->{debug});
						$svrUrl{$n} = $u;
					}

					undef @dlServer;
					@dlServer = keys %svrUrl;

					$loop = 0 if($loop > $#dlServer);
					$downloadUrl = $svrUrl{ $dlServer[$loop] };
				}

				$ie->Content() =~ /\| (\d+) KB/;
				my $fileSize = $1;

				print "\r  downloading: $downloadUrl  $fileSize\n";

				#system("wget --progress=bar $downloadUrl");
				system($ie->{dltool} . ' ' . $downloadUrl);
				
				$loop++;
				last;
			}
		}
	}
}

sub _delay() {
    my $delayk = shift;

    for (my $i = $delayk ; $i >= 0 ; $i-- ) {
    	sleep 1;
		`hostname`;
		printf "\r  wait :\t        %3d seconds", $i ;
    }
}

sub _getTime(){
	my @lc_time = localtime;
	sprintf("%02d:%02d:%02d", @lc_time[2,1,0]);
}

1;
__END__

# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Win32::IEAutomation::RapidShare - Perl extension for downloading files hosted by RapidShare

=head1 SYNOPSIS

  use Win32::IEAutomation::RapidShare;

  my $ie = Win32::IEAutomation::RapidShare->new(
  	taskName     => 'box180FPS',
	debug        => 1,
	links        => \@rsURL,
	loopServer   => 'yes',
	stopIfBroken => 'yes'
	startTime    => '17:02',
	stopTime     => '09:00'
  );

  my $url = 'http://rapidshare.com/users/ISWUF5';

  $num = $ie->add_rslinks( url => $url );

  $num = $ie->add_rslinks( array => \@uuu );

  $num = $ie->add_rslinks( file => "rsList.txt");

  $num = $ie->check_rslinks();
  
  $ie->downloadrs();

=head1 DESCRIPTION

This module uses RapidShare free user account to batch download files. 
No interactive user action is involved. If waiting between downloads is annoy, 
please upgrade to premium users. Time works for you.

=head1 METHODS

=head2 Win32::IEAutomation::RapidShare->new( )

This is the constructor for new Internet Explorer instance through Win32::OLE. Calling this function will create a perl object 
which internally contains a automation object for internet explorer.
In addition to Win32::IEAutomation's options, RapidShare specific options are supported.

=over 4

=item * taskName

taskName is optional. The URLs list will be saved to a text file. The default name is rapidshare.

=item * visible

It sets the visibility of Internet Explorer window. 
The default value is 0, means by default it will be invisible if you don't set to 1.

=item * debug

It prints more information in DOS prompt if it is defined. By default the debug mode is off.

=item * dltool

Specify your favorite download utility. The default tool is lwp-download that comes with LWP. You also can specify utility's option.

=item * links

Pass download URLs as an array reference to constructor.

=item * loopServer

There are bunch of alternative download URLs that are point to different server. If this option is defined, 
different server's URL will be used for each file download. By exam the onscreen download information - download speed and time,
users might figure out which server is fast, and then users could use that particular server later.

=item * preferServer

Specify the download server that users like to use for downloading.

=item * stopIfBroken

RapidShare hosted file has max file size limitation (200M?). Lots of big files are zipped and splitted before uploading to RapidShare. 
So please always validate all links firstly. If any link is broken, it might not a good idea to continue to download files. You could end
up with files that cannot be merged and uncompressed.

=item * startTime

Specify time to start downloading files. So users can avoid internet rush hour.

=item * stopTime

Specify time to stop downloading files.

=back

=head2 $ie->add_rslinks( )

Import download links from different resource. Duplicated links will be removed from download list. This method returns the number of links.

=over 4

=item * array 

Get from a array reference: $ie->add_rslinks( array => \@uuu )

=item * file 

Get from a URL list file: $ie->add_rslinks( file => "rsList.txt")

=item * url

Get from a URL whose page has links: $ie->add_rslinks( url => 'http://rapidshare.com/users/ISWUF5' )

=back

=head2 $ie->check_rslinks( )

Validate all links by using RapidShare file checking tool. This method returns the number of broken links. if stopIfBroken is defined 
and some links broken, the script will exit.

=head2 $ie->downloadrs( )

Download all links you jus imported.

=head1 Sample Script rs.pl to download a single file

	use Win32::IEAutomation::RapidShare;

	my $ie = Win32::IEAutomation::RapidShare->new(
		links =>[$ARGV[0]],
	);

	$ie->check_rslinks();
	$ie->downloadrs();

=head1 SEE ALSO

L<Win32::IEAutomation>.

=head1 AUTHOR

Jing Kang <kxj@hotmail.com>

=cut
