package Carbon::Anthracite::Plugins::Graphite;
use parent 'Carbon::Anthracite::Plugin';
use strict;
use warnings;

use feature 'say';


use Carbon::Graphite;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new;

	$self->engine($args{engine} // Carbon::Graphite->new);

	return $self
}



sub engine { @_ > 1 ? $_[0]{anthracite_plugin_graphite__engine} = $_[1] : $_[0]{anthracite_plugin_graphite__engine} }





# api methods


sub set_template {
	my ($self, $name, $template) = @_;
	say "created template '$name'";
	$self->engine->template($name => $template);
}

sub render_template {
	my ($self, $name, $arg) = @_;
	return $self->engine->template($name)->execute($arg)
}







# overridden plugin methods


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




sub code_header {
	my ($self, $data) = @_;
	return
'
our $graphite = $runtime->{anthracite_plugin_graphite__interface};
'
}

sub create_runtime {
	my ($self, $compiled, $runtime) = @_;
	$runtime->{anthracite_plugin_graphite__interface} = $self;
	return $runtime
}




1;
