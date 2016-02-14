package Carbon::Limestone::Query;
use parent 'Carbon::Limestone::Message';
use strict;
use warnings;



sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);
	return $self
}


1;
