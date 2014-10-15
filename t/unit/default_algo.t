use strict;
use lib 'lib';
use feature qw(say);
use Test::More;
use Test::Warn;
use File::Basename qw(dirname);
use Data::Dumper;
use utf8;

my $CLASS = 'Geo::Address::Formatter';
use_ok($CLASS);

my $path = dirname(__FILE__) . '/test_conf1';
my $GAF = $CLASS->new( conf_path => $path );

my $rh_components = {
    "one" => "ONE",
    "two" => "TWO",
    "three" => "THREE",
    "four" => "FOUR",
 };

warning_like {
  is(
    $GAF->_clean( $GAF->_default_algo($rh_components) ), 
    'FOUR, ONE, TWO, THREE'
  );
} qr/not sure where to put this/, 'got warning';

done_testing();