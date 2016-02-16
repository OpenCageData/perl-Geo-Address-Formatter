use strict;
use lib 'lib';
use feature qw(say);
use Data::Dumper;
use File::Basename;
use File::Find::Rule;
use File::Slurper 'read_text';
use File::Spec;
use Getopt::Long;
use Test::Exception;
use Test::More;
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
my $verbose = 0;

GetOptions ( 
    'country:s'  => \$input_country,
    'verbose'    => \$verbose,
);
if ( $input_country ){
  $input_country = lc($input_country);
}

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
        my $rh_testcase = shift;

        my $expected = $rh_testcase->{expected};
        my $actual = $GAF->format_address($rh_testcase->{components});

        #warn "e1 $expected\n";
        #warn "a1 $actual\n";
        if (0) { # turn on for char by char comparison 
            my @e = (split//, $expected);
            my @a = (split//, $actual); 
            my $c = 0;
            foreach my $char (@e){
                if ($e[$c] eq $a[$c]){
                    warn "same $c same $a[$c]";
                } else {
                    warn "not same $c " . $e[$c] . ' ' . $a[$c] . "\n";
                } 
                $c++;
            }
            #$expected =~ s/\n/, /g;
            #$actual =~ s/\n/, /g;
            #warn "e2 $expected\n";
            #warn "a2 $actual\n";
        }

        is(
          $actual,
          $expected,
          $country . ' - ' . $rh_testcase->{description}
        );
    }

    foreach my $filename (@files){

        my $country = basename($filename);
        $country =~ s/\.\w+$//; # us.yaml => us

        if (defined($input_country) && $input_country){
            if ($country ne $input_country){
                if ($verbose){
                    warn "skipping $country tests";     
                }
                next;
            }
        }

        my @a_testcases = ();
        lives_ok {
            @a_testcases = LoadFile($filename);
        } "parsing file $filename";

        {
          my $text = read_text($filename);

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
          if ( $text !~ m/\n$/ ){
              like(
                $text,
                qr!\n$!,
                'file doesnt end in newline. This will cause parsing errors'
             );

          }

        }
        foreach my $rh_testcase (@a_testcases){
            _one_testcase($country, $rh_testcase);
        }
    }
}

done_testing();