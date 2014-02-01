# dxclusterspy

This Perl script archives amateur radio DX Cluster spots to a database
for subsequent data analysis. DX Cluster spots report interesting
activity on amateur radio frequencies and are monitored by many
radio amateurs.

# Requirements

This Perl script makes use of `Net::Telnet` and `DBI` to access either
sqlite or mysql databases. Please make sure to install the required
modules and database drivers via CPAN before running this script.

# Usage

Prior to using dxclusterspy, edit the configuration variables in the
dxclusterspy.pl script. This includes specifying the desired database,
your call sign, and the remote DX Cluster server.

After configuration, launch dxclusterspy from the commandline:
```
./dxclusterspy.pl
```

# Database Usage Examples

Once DX Cluster spots are collected, the data can be analyzed.
Assuming all data is stored in a local sqlite database, launch the
database client as follows:
`sqlite3 dxclusterspy.db`

Show all spots stored in the database (warning, this will literally
print the entire database. So don't perform this on larger databases
and specify a limit instead, e.g., `SELECT * FROM dxclusterspots LIMIT 5;`! 
`SELECT * FROM dxclusterspots;`

Get the number of spots stored in the database:
`SELECT COUNT(*) FROM dxclusterspots;`

Show all spots in which N1MM was spotted:
`SELECT * FROM dxclusterspots WHERE DXCall = 'N1MM';`

Show the number of spots per band:
`SELECT BAND, COUNT(*) FROM dxclusterspots;`

You can read the data into [GNU R](http://www.r-project.org/) for
proper statistical analysis.
