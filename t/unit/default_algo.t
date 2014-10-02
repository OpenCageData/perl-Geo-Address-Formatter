use strict;
use lib 'lib';
use feature qw(say);
use Test::More;
use File::Basename qw(dirname);
use Data::Dumper;
use utf8;

my $CLASS = 'Geo::Address::Formatter';
use_ok($CLASS);

my $path = dirname(__FILE__) . '/test_conf1';
my $GAF = $CLASS->new( conf_path => $path );


#y $rh_components = {
#     "bank" => "Commerzbank",
#     "city" => "Münster",
#     "city_district" => "Münster-Mitte",
#     "country" => "Germany",
#     "country_code" => "de",
#     "county" => "Münster",
#     "house_number" => 52,
#     "neighbourhood" => "Josef",
#     "postcode" => 48153,
#     "road" => "Hammer Straße",
#     "state" => "North Rhine-Westphalia",
#     "state_district" => "Regierungsbezirk Münster",
#     "suburb" => "Innenstadtring"
#};

#is(
	# $GAF->_clean( $GAF->_default_algo($rh_components) ), 
	# 'Commerzbank, 52, Hammer Straße, Josef, Innenstadtring, Münster-Mitte, Münster, Münster, 48153, Regierungsbezirk Münster, North Rhine-Westphalia, Germany'
#;



my $rh_components = {
    "one" => "ONE",
    "two" => "TWO",
    "three" => "THREE",
    "four" => "FOUR",
 };

is(
  $GAF->_clean( $GAF->_default_algo($rh_components) ), 
  'FOUR, ONE, TWO, THREE'
);


done_testing();