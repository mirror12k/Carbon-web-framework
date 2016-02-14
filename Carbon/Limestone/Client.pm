package Carbon::Limestone::Client;
use strict;
use warnings;

use feature 'say';


use Carbon::Limestone::Query;
use Carbon::Limestone::Connection;

sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->connection(Carbon::Limestone::Connection->new);
	$self->connect($args{hostport}) if exists $args{hostport};

	return $self
}

sub connection { @_ > 1 ? $_[0]{limestone_client__connection} = $_[1] : $_[0]{limestone_client__connection} }


sub connect {
	my ($self, $hostport) = @_;
	$self->connection->connect_client($hostport);
}

sub query {
	my ($self) = shift;
	my %query = @_;
	$self->connection->write_query(Carbon::Limestone::Query->new(%query));
	return $self->connection->read_result;
}


1;

