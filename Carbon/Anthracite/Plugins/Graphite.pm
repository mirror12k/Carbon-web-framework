package Carbon::Anthracite::Plugins::Graphite;
use parent 'Carbon::Anthracite::Plugin';
use strict;
use warnings;

use feature 'say';





sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new;

	$self->templates({});

	return $self
}



sub templates { @_ > 1 ? $_[0]{anthracite_graphite__templates} = $_[1] : $_[0]{anthracite_graphite__templates} }



sub compile_token {
	my ($self, $token) = @_;
	my ($token_type, $raw, $tag_type, $tag_data) = @$token;
	if ($token_type eq 'directive' and $tag_type eq 'graphite') {
		$self->parse_graphite($tag_data);
		return '', undef
	} else {
		return '', $token
	}
}



sub parse_graphite {
	my ($self, $text) = @_;
	
}




sub code_header {
	my ($self, $data) = @_;
	return
'
our $graphite = $runtime->{anthracite_graphite__interface};
'
}

sub create_runtime {
	my ($self, $compiled, $runtime) = @_;
	$runtime->{anthracite_graphite__interface} = $self;
	return $runtime
}




1;
