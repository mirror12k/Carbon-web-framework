package Carbon::Limestone::Message;
use strict;
use warnings;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->type($args{type}) if exists $args{type};
	$self->data($args{data}) if exists $args{data};
	$self->id($args{id}) if exists $args{id};

	return $self
}

sub type { @_ > 1 ? $_[0]{limestone_message__type} = $_[1] : $_[0]{limestone_message__type} }
sub data { @_ > 1 ? $_[0]{limestone_message__data} = $_[1] : $_[0]{limestone_message__data} }
sub id { @_ > 1 ? $_[0]{limestone_message__id} = $_[1] : $_[0]{limestone_message__id} }


sub serialize {
	my ($self) = @_;

	my $data = {};
	$data->{type} = $self->type if defined $self->type;
	$data->{data} = $self->data if defined $self->data;
	$data->{id} = $self->id if defined $self->id;

	return $data
}


1;
