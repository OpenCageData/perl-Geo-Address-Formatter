# ABSTRACT: take structured address data and format it according to the various global/country rules

package Geo::Address::Formatter;

use strict;
use warnings;

use Mustache::Simple;
use Try::Tiny;
use Clone qw(clone);
use File::Basename qw(dirname);
use File::Find::Rule;
use List::Util qw(first);
use Data::Dumper;
use YAML qw(Load LoadFile);

my $tache = Mustache::Simple->new;

=head1 DESCRIPTION

You have a structured postal address (hash) and need to convert it into a
readable address based on the format of the address country.

For example, you have:

  {
    house_number => 12,
    street => 'Some street',
    postcode => 45678,
    city => 'Nirvana'
  }

you need:

  Great Britain: Some street 12, Nirvana 45678  
  France: 12 Some street, 45678 Nirvana
  Germany: Some street 12, 45678 Nirvana

It gets more complicated with 100 countries and dozens more address
components to consider.

This module comes with a minimal configuration to run tests. Instead of
developing your own configuration please use (and contribute to)
those in https://github.com/lokku/address-formatting 
which includes test cases. 

Together we can address the world!

=head1 SYNOPSIS

  #
  # get the templates (or use your own) 
  # git clone git@github.com:lokku/address-formatting.git
  # 
  my $GAF = Geo::Address::Formatter->new( conf_path => '/path/to/templates' );
  my $components = { ... }
  my $text = $GAF->format_address($components, { country => 'FR' } );

=method new

  my $GAF = Geo::Address::Formatter->new( conf_path => '/path/to/templates' );

Returns one instance. The conf_path is required.

=cut

sub new {
    my ($class, %params) = @_;
    
    my $self = {};
    my $conf_path = $params{conf_path} || die "no conf_path set";
    bless( $self, $class );
    
    $self->_read_configuration($conf_path);
    return $self;
}

sub _read_configuration {
    my $self = shift;
    my $path = shift;

    my @a_filenames = 
        File::Find::Rule->file()->name( '*.yaml' )->in($path.'/countries');

    # FIXME - not sure about this logic
    # seems like it will overwrite $self->{templates} if multiple files found
    foreach my $filename ( @a_filenames ){
        try {
            $self->{templates} = LoadFile($filename);
        }
        catch {
            warn "error parsing country configuration in $filename: $_";
        };
    }
    # warn Dumper \@files;

    try {
        my @c = LoadFile($path . '/components.yaml');
        # warn Dumper \@c;
        $self->{ordered_components} = 
            [ map { $_->{name} => ($_->{aliases} ? @{$_->{aliases}} : ()) } @c];
    }
    catch {
        warn "error parsing component configuration: $_";
    };

    $self->{state_codes} = {};
    if ( -e $path . '/state_codes.yaml'){
        try {
            my $rh_c = LoadFile($path . '/state_codes.yaml');
            # warn Dumper $rh_c;
            $self->{state_codes} = $rh_c;
        }
        catch {
            warn "error parsing component configuration: $_";
        };
    }
    return;
}

=head2 format_address

  my $text = $GAF->format_address(\%components, \%options );

Given a structures address (hashref) and options (hashref) returns a
formatted address.

The only option you can set currently is 'country' which should
be an uppercase ISO_3166-1_alpha-2 code, e.g. 'UK' for Great Britain.
If ommited we try to find the country in the address components.

=cut

sub format_address {
    my $self       = shift;
    my $rh_components = clone(shift) || return;
    my $rh_options = shift || {};

    my $cc = $rh_options->{country} 
            || $self->_determine_country_code($rh_components) 
            || '';

    my $rh_config = $self->{templates}{uc($cc)} || $self->{templates}{default};
    my $template_text = $rh_config->{address_template};

    #print STDERR "t text " . Dumper $template_text;
    #print STDERR "comp " . Dumper $rh_components;

    # do we have the minimal components for an address?
    # or should we instead fall back?
    $self->_apply_replacements($rh_components, $rh_config->{replace});
    $self->_add_state_code($rh_components);

    if (!$self->_minimal_components($rh_components)){
        $template_text = 
            $rh_config->{fallback_template}
            || $self->{templates}{default}{fallback_template}
            || $rh_config->{address_template};  # if there is no fallback
    }

    $rh_components->{attention} = join(', ', map { $rh_components->{$_} } @{ $self->_find_unknown_components($rh_components)} );

    my $text = $self->_render_template($template_text, $rh_components);
    $text = $self->_clean($text);
    return $text;
}

sub _minimal_components {
    my $self = shift;
    my $rh_components = shift || return;
    my @required_components = qw(road postcode);
    my $missing = 0;  # number of required components missing
  
    my $minimal_threshold = 2;
    foreach my $c (@required_components){
        $missing++ if (!defined($rh_components->{$c}));
        return 0 if ($missing == $minimal_threshold);
    }
    return 1;
}

sub _determine_country_code {
    my $self       = shift;
    my $components = shift || return;

    # FIXME - validate it is a valid country
    if (my $cc = $components->{country_code} ){
        return if ( $cc !~ m/^[a-z][a-z]$/i);
        return 'GB' if ($cc =~ /uk/i);
        return uc($cc);
    }
    return;
}

# sets and returns a state code
sub _add_state_code {
    my $self       = shift;
    my $components = shift;

    ## TODO: what if the cc was given as an option?
    my $cc = $self->_determine_country_code($components) || '';

    return if $components->{state_code};
    return if !$components->{state};

    if ( my $mapping = $self->{state_codes}{$cc} ){
        foreach ( keys %$mapping ){
            if ( uc($components->{state}) eq uc($mapping->{$_}) ){
                $components->{state_code} = $_;
            }
        }
    }
    return $components->{state_code};
}

sub _apply_replacements {
    my $self        = shift;
    my $components  = shift;
    my $raa_rules   = shift;

    foreach my $key ( keys %$components ){
        foreach my $ra_fromto ( @$raa_rules ){

            try {
                my $regexp = qr/$ra_fromto->[0]/;
                $components->{$key} =~ s/$regexp/$ra_fromto->[1]/;
            }
            catch {
                warn "invalid replacement: " . join(', ', @$ra_fromto)
            };
        }
    }
    return $components;
}

# " abc,,def , ghi " => 'abc, def, ghi'
sub _clean {
    my $self = shift;
    my $out  = shift // '';
    $out =~ s/[,\s]+$//;
    $out =~ s/^[,\s]+//;

    $out =~ s/,\s*,/, /g; # multiple commas to one   
    $out =~ s/\s+,\s+/, /g; # one space behind comma

    $out =~ s/\s\s+/ /g; # multiple whitespace to one
    $out =~ s/^\s+//;
    $out =~ s/\s+$//;
    return $out;
}

sub _render_template {
    my $self             = shift;
    my $template_content = shift;
    my $components       = shift;

    # Mustache calls it context
    my $context = clone($components);

    $context->{first} = sub {
        my $text = shift;
        $text = $tache->render($text, $components);
        my $selected = first { length($_) } split(/\s*\|\|\s*/, $text);
        return $selected;
    };

    $template_content =~ s/\n/, /sg;
    my $output = $tache->render($template_content, $context);
    
    $output = $self->_clean($output);
    return $output;
}

# note: unsorted list because $cs is a hash!
# returns []
sub _find_unknown_components {
    my $self       = shift;
    my $components = shift;

    my %h_known = map { $_ => 1 } @{ $self->{ordered_components} };
    my @a_unknown = grep { !exists($h_known{$_}) } keys %$components;

    return \@a_unknown;
}

sub _default_algo {
    my $self = shift;
    my $cs = shift || return;

    my @values = ();

    # upper case country code
    if ( my $ccode = $cs->{country_code} ){
        $cs->{country_code} = uc($ccode);
    }

    # now do the location pieces
    foreach my $k (@{ $self->{ordered_components} }){
        next unless ( exists($cs->{$k}) );
        next if ( $k eq 'country_code' && $cs->{'country'} );

        push(@values, $cs->{$k});
    }

    # get the ones we missed previously
    # FIXME - this is bad, we're just shoving stuff to the start
    foreach my $k ( @{ $self->_find_unknown_components($cs) } ) {
        warn "not sure where to put this: $k";
        ## add to the front
        unshift(@values, $cs->{$k});
    }
    return join(', ', @values);
}

1;
