package Carbon::Limestone::Result;
use parent 'Carbon::Limestone::Message';
use strict;
use warnings;



sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	$self->error($args{error}) if exists $args{error};

	return $self
}

sub error { @_ > 1 ? $_[0]{limestone_result__error} = $_[1] : $_[0]{limestone_result__error} }



sub serialize {
	my ($self) = @_;

	my $data = $self->SUPER::serialize;
	$data->{error} = $self->error if defined $self->error;

	return $data
}


sub is_success { return $_[0]->type eq 'success' }
sub is_error { return $_[0]->type eq 'error' }


1;


