package Carbon::Limestone::Message;
use strict;
use warnings;



sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->type($args{type}) if exists $args{type};
	$self->collection($args{collection}) if exists $args{collection};
	$self->data($args{data}) if exists $args{data};

	return $self
}

sub type { @_ > 1 ? $_[0]{limestone_message__type} = $_[1] : $_[0]{limestone_message__type} }
sub collection { @_ > 1 ? $_[0]{limestone_message__collection} = $_[1] : $_[0]{limestone_message__collection} }
sub data { @_ > 1 ? $_[0]{limestone_message__data} = $_[1] : $_[0]{limestone_message__data} }


sub serialize {
	my ($self) = @_;

	my $data = {};
	$data->{type} = $self->type if defined $self->type;
	$data->{collection} = $self->collection if defined $self->collection;
	$data->{data} = $self->data if defined $self->data;

	return $data
}


1;