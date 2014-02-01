#!/usr/bin/perl

use Net::Telnet ();
use DBI;

#############################################################################
# Configuration
#
# Please adapt the parameters below to your needs.
#############################################################################
my $my_call = 'N0CALL';
my $host = 'dxc.ab5k.net';
my $port = '23';
# Configure the database system to use
my $dbsystem = "sqlite";
# my $dbsystem = "mysql";

# In the case of MySQL, please also specify the database credentials
# my $dbhost = "localhost";
# my $database = "";
# my $dbuser = "";
# my $dbpwd = "";


#############################################################################

my $usear17 = 1;
my $rawlogfile = "rawlog.dxc";
my $prettyprintfile = "spots.dxc";
my $errorfile = "errors.dxc";

my $dbh;

if ($dbsystem eq "sqlite") {
	if(!grep(/SQLite/, DBI->available_drivers())) {
		print "SQLite driver missing. Please issue \n";
		exit(1);
	}

	$dbh = DBI->connect(
		"dbi:SQLite:dbname=dxclusterspy.db",
		"",
		"",
		{ RaiseError => 1 },
	) or die $DBI::errstr;

} elsif ($dbsystem eq "mysql") {
	if(!grep(/mysql/, DBI->available_drivers())) {
		print "MySQL driver missing. Please issue \n";
		exit(1);
	}

	$dbh = DBI->connect(
		"DBI:mysql:$database;host=$dbhost",
		$dbuser, $dbpwd)
	or die("Can't connect to MySQL server!\n");
}

# Check if the table exists
my $sth = $dbh->table_info("", "", "dxclusterspots", "TABLE");
if (!$sth->fetch) {
	print "Dxclusterspots table doesn't, creating it...\n";

	my $sql = "";
	if($dbsystem eq "sqlite") {
		$sql = <<END;
		CREATE TABLE IF NOT EXISTS dxclusterspots (
			`DXCall` varchar(10) NOT NULL,
			`QRG` float NOT NULL,
			`Spotter` varchar(10) NOT NULL,
			`Note` varchar(255) NOT NULL,
			`Spottime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
			`Inserttime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
			`Band` tinyint(3) DEFAULT NULL,
			`Mode` varchar(10) DEFAULT NULL,
			`PrefixDXCall` varchar(10) DEFAULT NULL, 
			`PrefixSpotter` varchar(10) DEFAULT NULL,
			`SpotPlausible` tinyint(1) DEFAULT NULL,
			PRIMARY KEY (`DXCall`,`Inserttime`,`Band`,`Mode`,`PrefixDXCall`)
		);
END
	} elsif ($dbsystem eq "mysql") {
		$sql = <<END;
		CREATE TABLE IF NOT EXISTS `dxclusterspots` (
			`DXCall` varchar(10) NOT NULL,
			`QRG` float unsigned NOT NULL,
			`Spotter` varchar(10) NOT NULL,
			`Note` varchar(255) NOT NULL,
			`Spottime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
			`Inserttime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
			`Band` tinyint(3) unsigned DEFAULT NULL,
			`Mode` varchar(10) DEFAULT NULL,
			`PrefixDXCall` varchar(10) DEFAULT NULL COMMENT 'DXCC of the reported DX station',
			`PrefixSpotter` varchar(10) DEFAULT NULL COMMENT 'DXCC of the reporting station',
			`SpotPlausible` tinyint(1) DEFAULT NULL,
			KEY `DXCall` (`DXCall`,`Inserttime`,`Band`,`Mode`,`PrefixDXCall`)
		) ENGINE=MyISAM DEFAULT CHARSET=latin1;
END
	}

	my $sth = $dbh->prepare($sql);
	$sth->execute() or die("Error while creating table: $DBI::errstr\n");
	print "Table created.\n";
}

my $sql = "";
if ($dbsystem eq "mysql") {
	$sql = "INSERT INTO dxclusterspots (DXCall, QRG, Spotter, Note, Spottime, Inserttime, Band, Mode, PrefixDXCall, PrefixSpotter, SpotPlausible) VALUES (?,?,?,?,?,NOW(),?,?,?,?,?)";
} elsif ($dbsystem eq "sqlite") {
	$sql = "INSERT INTO dxclusterspots (DXCall, QRG, Spotter, Note, Spottime, Inserttime, Band, Mode, PrefixDXCall, PrefixSpotter, SpotPlausible) VALUES (?,?,?,?,?,DateTime('now'),?,?,?,?,?)";
}
my $sth = $dbh->prepare($sql);

while(1) {
	my $t = Net::Telnet->new(Host => $host, Port => $port, Timeout => 300);

	open RAWDX, ">>$rawlogfile" or die("Can't open $rawlogfile for writing!\n");
	open PRETTYPRINT, ">>$prettyprintfile" or die("Can't open $prettyprintfile for writing!\n");
	open ERRORS, ">>$errorfile" or die("Can't open $errorfile for writing!\n");

	# let the program die whenever there is an error
	$t->errmode("die");

	$t->waitfor('/Please enter your call:/');
	$t->print($my_call);
	#$t->waitfor('/Please enter a valid callsign:/');
	#$t->print($my_call);
	$t->waitfor('/arc6>/');

	if ($usear17 == 1) {
		$t->print('set/dx_arpc on');
	}

	my $line = "";
	while($line = $t->getline()) {
		print RAWDX $line;

		my $spotter;
		my $qrg;
		my $dxcall;
		my $note;
		my $spottime;
		my $timesql = "0000-00-00 00:00:00";

		# Optional fields
		my $band; # band as int, e.g., "30"
		my $mode; # mode used in that band segment, e.g., "CW"
		my $prefixdx; # Prefix of the DX station
		my $prefixspotter;
	
		# if spot passed plausibility check. Set to 0 if not
		my $plausible = 1;

		# DX de K6AAB:      7150.0  TX7M         no takers                      1216Z
		if ($usear17 == 0 && $line =~ /^DX de ([A-Z0-9\/]+):[^0-9]+([0-9\.]+)\W+([A-Z0-9\/]+)\W+(\w+)/) {
			$spotter = $1;
			$qrg = $2;
			$dxcall = $3;
			$note = $4;
		}

		if ($usear17 == 1 && $line =~ /^AR17/) {
			my @fields = split(/\^/, $line);
			$qrg = $fields[2];
			$dxcall = $fields[3];
			my $spotdate = $fields[4];
			$spottime = $fields[5];
			$note = $fields[6];
			$spotter = $fields[7];

			$band = $fields[10];
			$mode = $fields[11];
			$prefixdx = $fields[9];
			$prefixspotter = $fields[15];

			# Convert spot time to a MySQL compatible format
			my $hour = -1;
			my $min = -1;
			if ($spottime =~ /([0-9]{2})([0-9]{2})Z/) {
		    $hour = $1;
		  	$min = $2;
			}

			my $year = "0000";
			my $mon = "00";
			my $day = "00";
			if ($spotdate =~ /([0-9]{1,2})-([A-Za-z]{3})-([0-9]{4})/) {
    		$day = $1;
		    $year = $3;
		    if ($2 =~ /Jan/) { $mon = "01"; }
		    if ($2 =~ /Feb/) { $mon = "02"; }
		    if ($2 =~ /Mar/) { $mon = "03"; }
		    if ($2 =~ /Apr/) { $mon = "04"; }
		    if ($2 =~ /May/) { $mon = "05"; }
		    if ($2 =~ /Jun/) { $mon = "06"; }
		    if ($2 =~ /Jul/) { $mon = "07"; }
		    if ($2 =~ /Aug/) { $mon = "08"; }
		    if ($2 =~ /Sep/) { $mon = "09"; }
		    if ($2 =~ /Oct/) { $mon = "10"; }
		    if ($2 =~ /Nov/) { $mon = "11"; }
				if ($2 =~ /Dec/) { $mon = "12"; }
			}
			$timesql = "$year-$mon-$day $hour:$min:00";

			# Plausibility checks
			if ($fields[0] != "AR17") {
				$plausible = 0;
				print "ERROR: Spot does not start with AR17: $fields[0]\n";
				print ERRORS "ERROR: Spot does not start with AR17: $fields[0]\n";
				print ERRORS $line;
			}
			if ($fields[1] != "1") {
				$plausible = 0;
				print "ERROR: first field not 1: $fields[1]\n";
				print ERRORS "ERROR: first field not 1: $fields[1]\n";
				print ERRORS $line;
			}
			if ($fields[18] != "~") {
				$plausible = 0;
				print "ERROR: last field not ~: $fields[18]\n";
				print ERRORS "ERROR: last field not ~: $fields[18]\n";
				print ERRORS $line;
			}
			if (not $fields[2] =~ /[0-9]+\.[0-9]+/) {
				$plausible = 0;
				print "ERROR: QRG in wrong format: $fields[2]\n";
				print ERRORS "ERROR: QRG in wrong format: $fields[2]\n";
				print ERRORS $line;
			}
			if (not $fields[5] =~ /[0-9]+Z/) {
				$plausible = 0;
				print "ERROR: spot time in wrong format: $fields[5]\n";
				print ERRORS "ERROR: spot time in wrong format: $fields[5]\n";
				print ERRORS $line;
			}
			if ($day < 1 || $day > 31) {
				$plausible = 0;
				print "ERROR: day field wrong: $day, was $spotdate\n";
				print ERRORS "ERROR: day field wrong: $day, was $spotdate\n";
				print ERRORS $line;
			}
			if ($mon < 1 || $mon > 12) {
				$plausible = 0;
				print "ERROR: month field wrong: $mon, was $spotdate\n";
				print ERRORS "ERROR: month field wrong: $mon, was $spotdate\n";
				print ERRORS $line;
			}
			if ($year < 2000 || $year > 2100) {
				$plausible = 0;
				print "ERROR: year field wrong: $year, was $spotdate\n";
				print ERRORS "ERROR: year field wrong: $year, was $spotdate\n";
				print ERRORS $line;
			}
			if ($hour < 0 || $hour > 23) {
				$plausible = 0;
				print "ERROR: hour field wrong: $hour, was $spottime\n";
				print ERRORS "ERROR: hour field wrong: $hour, was $spottime\n";
				print ERRORS $line;
			}
			if ($min < 0 || $min > 59) {
				$plausible = 0;
				print "ERROR: minute field wrong: $min, was $spottime\n";
				print ERRORS "ERROR: minute field wrong: $min, was $spottime\n";
				print ERRORS $line;
			}

			# produce the classical output
			print "DX de $spotter:\t$qrg  $dxcall\t$note\t$spottime\n";
			print PRETTYPRINT "DX de $spotter:\t$qrg  $dxcall\t$note\t$spottime\n";

			# Insert into database
			eval {
				$sth->execute($dxcall, $qrg, $spotter, $note, $timesql, $band, $mode, $prefixdx, $prefixspotter, $plausible) or print ERRORS "ERROR: SQL injection error: $DBI::errstr\n";
			};
			if( $@ ) {
				warn "Database error: $DBI::errstr\n";
				#$dbh->rollback();
			}

			# Uncomment the code below when you wish the receive email alerts when
			# certain calls are spotted on the cluster. This required a working
			# installation and configuration of mutt to send mail.
			#if ($dxcall =~ /N0CALL/ || $dxcall =~ /S0ME/ || $dxcall =~ /C4LL/) {
			#	system "echo \"$dxcall spotted by $spotter on $qrg\" | mutt -s \"$dxcall spotted by $spotter on $qrg\" email\@me.org";
			#}
		}
	}

	$t->close();
	close(RAWDX);
	close(PRETTYPRINT);
	close(ERRORS);
} # end while

$sth->finish();
$dbh->disconnect();
