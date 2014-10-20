use strict;
use lib 'lib';
use feature qw(say);
use Test::More;
use Test::Exception;
use Data::Dumper;
use File::Basename;
use File::Spec;
use File::Find::Rule;
use File::Slurp;
use Getopt::Long;
use YAML qw(LoadFile);

use utf8;

# nicer output for diag and failures, see
# http://perldoc.perl.org/Test/More.html#CAVEATS-and-NOTES
my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";

my $af_path = dirname(__FILE__) . '/../../address-formatting';

my $path = $af_path . '/testcases/';
my $input_country;
GetOptions ( 
    'country:s'  => \$input_country,
);
$input_country = lc($input_country);

ok(1);

if ( -d $path ){

    my $path2 = $af_path . '/conf/';

    my @files = File::Find::Rule->file()->name( '*.yaml' )->in( $path );

    ok(scalar(@files), 'found at least one file');

    my $CLASS = 'Geo::Address::Formatter';
    use_ok($CLASS);
    my $GAF = $CLASS->new( conf_path => $path2 );

    sub _one_testcase {
        my $country    = shift;
        #next if ($country ne 'de');
        my $rh_testcase = shift;
        #next if ($rh_testcase->{expected} !~ m/Köln/);
        is(
          $GAF->format_address($rh_testcase->{components}),
          $rh_testcase->{expected},
          $country . ' - ' . $rh_testcase->{description}
        );
    }

    foreach my $filename (@files){

        my $country = basename($filename);
        $country =~ s/\.\w+$//; # us.yaml => us

        if (defined($input_country) && $input_country){
            if ($country ne $input_country){
                warn "skipping $country tests";     
                next;
            }
        }

        my @a_testcases = ();
        lives_ok {
            @a_testcases = LoadFile($filename);
        } "parsing file $filename";

        {
          my $text = read_file($filename);

          ## example "Stauffenstra\u00dfe" which should be "Stauffenstraße"
          if ( $text =~ m/\\u00/ ){
              unlike(
                $text,
                qr!\\u00!,
                'don\'t use Javascript utf8 encoding, use characters directly'
             );
          }

          if ( $text =~ m/\t/ ){
              unlike(
                $text,
                qr/\t/,
                'there is a TAB in the YAML file. That will cause parsing errors'
              );
          }
        }
        foreach my $rh_testcase (@a_testcases){
            _one_testcase($country, $rh_testcase);
        }
    }
}

done_testing();