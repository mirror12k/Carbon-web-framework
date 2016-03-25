package Carbon::Limestone::Query;
use parent 'Carbon::Limestone::Message';
use strict;
use warnings;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->target($args{target}) if exists $args{target};

	return $self
}

sub target { @_ > 1 ? $_[0]{limestone_query__target} = $_[1] : $_[0]{limestone_query__target} }



sub serialize {
	my ($self) = @_;

	my $data = $self->SUPER::serialize;
	$data->{target} = $self->target if defined $self->target;

	return $data
}


1;
