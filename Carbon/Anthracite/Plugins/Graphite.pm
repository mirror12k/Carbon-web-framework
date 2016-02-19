package Carbon::Anthracite::Plugins::Graphite;
use parent 'Carbon::Anthracite::Plugin';
use strict;
use warnings;

use feature 'say';


use Carbon::Graphite;



# a plugin for hooking necessary compiler functions and to provide a runtime interface to the Graphite engine



sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new;

	$self->engine($args{engine} // Carbon::Graphite->new);

	return $self
}



sub engine { @_ > 1 ? $_[0]{anthracite_plugin_graphite__engine} = $_[1] : $_[0]{anthracite_plugin_graphite__engine} }





# api methods

sub get_template {
	my ($self, $name) = @_;
	return $self->engine->template($name);
}

sub set_template {
	my ($self, $name, $template) = @_;
	say "created template '$name'";
	$self->engine->template($name => $template);
}

sub render_template {
	my ($self, $name, $arg) = @_;
	if (ref $name) { # if the second argument is a template object
		return $name->execute($self, $arg)
	} else { # otherwise it's a name for retrieving a template
		return $self->engine->template($name)->execute($self, $arg)
	}
}







# overridden plugin methods


# capture any graphite directive tokens for the engine to compile
sub compile_token {
	my ($self, $token) = @_;
	my ($token_type, $raw, $tag_type, $tag_data) = @$token;
	if ($token_type eq 'directive' and $tag_type eq 'graphite') {
		return $self->compile_graphite($tag_data)
	} else {
		return '', $token
	}
}



sub compile_graphite {
	my ($self, $text) = @_;
	return $self->engine->compile_graphite_directive($text);
}



# add our runtime code for loading the api
sub code_header {
	my ($self, $data) = @_;
	return
'
our $graphite = $runtime->{anthracite_plugin_graphite__interface};
'
}

# parasitize the runtime object to transport our api
sub create_runtime {
	my ($self, $compiled, $runtime) = @_;
	$runtime->{anthracite_plugin_graphite__interface} = $self;
	return $runtime
}




1;
