package Carbon::Limestone::Client;
use strict;
use warnings;

use feature 'say';


use Carbon::Limestone::Query;
use Carbon::Limestone::Connection;

sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->connection(Carbon::Limestone::Connection->new);
	$self->connect($args{hostport}, $args{username}, $args{password}) if exists $args{hostport};

	return $self
}

sub connection { @_ > 1 ? $_[0]{limestone_client__connection} = $_[1] : $_[0]{limestone_client__connection} }


sub connect {
	my ($self, $hostport, $user, $password) = @_;
	$self->connection->connect_client($hostport, $user, $password);
}

sub query {
	my ($self, %query) = @_;
	$self->connection->write_query(Carbon::Limestone::Query->new(%query));
	return $self->connection->read_result;
}


sub create {
	my ($self, $target, $data) = @_;
	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'create',
		target => $target,
		data => $data,
	));
	return $self->connection->read_result_id_blocking($id)
}

sub list {
	my ($self, $target) = @_;
	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'list',
		target => $target,
	));
	return $self->connection->read_result_id_blocking($id)
}

sub delete {
	my ($self, $target) = @_;
	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'delete',
		target => $target,
	));
	return $self->connection->read_result_id_blocking($id)
}

sub client {
	my ($self, $target, $data) = @_;

	# request the client data
	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'client',
		target => $target,
		data => $data,
	));

	# get the result
	my $client_data = $self->connection->read_result_id_blocking($id);
	die "failed to get client: " . $client_data->error unless $client_data->is_success;

	# load the client package
	eval "use " . $client_data->data->{package};
	die "client package failed: $@" if $@;

	# create the new client
	my $client = $client_data->data->{package}->new($self->connection, $target, $client_data->data->{data});
	return $client
}

1;

