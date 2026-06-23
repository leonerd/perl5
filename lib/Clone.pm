use v5.40;
package Clone;
use XS::APItest;
our @EXPORT_OK = qw( clone );
use Exporter 'import';
sub clone { XS::APItest::sv_clone($_[0], 0); }

=head1 NAME

Clone - temporary hacking for unit tests

DO NOT MERGE TO BLEAD

=cut
