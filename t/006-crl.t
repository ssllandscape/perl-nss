use 5.10.1;
use strict;
use warnings;

use File::Temp;

use Test::More tests=>16;

my $dbdir;

BEGIN { 
	# use a temporary directory for our database...
	$dbdir = File::Temp->newdir();

	use_ok( 'NSS', (':dbpath', $dbdir) );
}


my $der = slurp("certs/rfc3280bis_cert1.cer");
my $cert = NSS::Certificate->new($der);

isa_ok($cert, 'NSS::Certificate');
is($cert->subject, 'CN=Example CA,DC=example,DC=com', 'subject');

$der = slurp("certs/thawte.crt");
my $thawte = NSS::Certificate->new_from_pem($der);
isa_ok($thawte, 'NSS::Certificate');
is($thawte->subject, 'CN=Thawte SGC CA,O=Thawte Consulting (Pty) Ltd.,C=ZA', 'subject');

my $crlder = slurp("certs/rfc3280bis_CRL.crl");
my $crl = NSS::CRL->new_from_der($crlder);

isa_ok($crl, 'NSS::CRL');
ok($crl->verify($cert, 1104537600), 'verify crl');
ok(!$crl->verify($thawte, 1104537600), 'verify crl');

my @entries = $crl->entries;
ok(scalar @entries == 1, '1 entry');
ok($entries[0]->serial == 12, 'crl entry serial');

# well, issuer finding only works if the issuer is in the db...
# and trust is. Because, what is the world without trust...
NSS::add_trusted_cert_to_db($cert, "issuer");

my $icert = $crl->find_issuer(1104537600);
isa_ok($icert, 'NSS::Certificate');
is($icert->subject, 'CN=Example CA,DC=example,DC=com', 'subject');

ok($crl->verify_db(1104537600), 'verify_db');
ok(!$crl->verify_db, 'verify_db');
is($crl->issuer, 'CN=Example CA,DC=example,DC=com', 'issuer');
ok($crl->version == 2, 'crl version is 2');

sub slurp {
  local $/=undef;
  open (my $file, shift) or die "Couldn't open file: $!";
  my $string = <$file>;
  close $file;
  return $string;
}
