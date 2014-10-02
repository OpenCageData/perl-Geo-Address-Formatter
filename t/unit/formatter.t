use strict;
use lib 'lib';
use Test::More;
use Test::Warn;
use Clone qw(clone);
use File::Basename qw(dirname);
use Data::Dumper;

my $CLASS = 'Geo::Address::Formatter';
use_ok($CLASS);

my $path = dirname(__FILE__) . '/test_conf1';
my $GAF = $CLASS->new( conf_path => $path );

{
  is(
    $GAF->_determine_country_code({ country_code => 'DE' }),
    'DE',
    'determine_country 1'
  );
  is(
    $GAF->_determine_country_code({ country_code => 'de' }),
    'DE',
    'determine_country 2'
  );

}



{
  is($GAF->_clean(undef),'', 'clean - undef');
  is($GAF->_clean(0),'0', 'clean - zero');
  my $rh_tests = {
    '  , abc , def ,, ghi , ' => 'abc, def, ghi'
  };

  while ( my($source, $expected) = each(%$rh_tests) ){
    is($GAF->_clean($source), $expected, 'clean - ' . $source);
  }

}


{
  is( $GAF->_add_state_code( {} ), undef );
  is( $GAF->_add_state_code( { country_code => 'br', state => 'Sao Paulo'} ), undef );
  is( $GAF->_add_state_code( { country_code => 'us', state => 'California'}), 'CA' );
}


{
  my $components = {
    street => 'Hello World',
  };

  is_deeply(
    $GAF->_apply_replacements(clone($components),[]),
    $components
  );

  is_deeply(
    $GAF->_apply_replacements(clone($components),[['^Hello','Bye'], ['d','t']]),
    {street => 'Bye Worlt'}
  );

  warning_like {
    is_deeply(
      $GAF->_apply_replacements(clone($components),[['((ll','']]),
      $components
    );
  } qr/invalid replacement/, 'got warning';


}

{
  is_deeply(
    $GAF->_find_unknown_components({ one => 1, four => 4}),
    ['four'],
    '_find_unknown_components'
  );
}


{
  my $template = 
  is(
    $GAF->_render_template(
        'abc {{#first}} {{one}} || {{two}} {{/first}} def',
        { two => 2 }
      ),
    'abc 2 def',
    '_render_template - first'
  );
}


done_testing();
