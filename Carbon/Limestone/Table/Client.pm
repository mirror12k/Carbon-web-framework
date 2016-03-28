package Carbon::Limestone::Table::Client;
use strict;
use warnings;

use feature 'say';

use Carbon::Limestone::Query;

sub new {
	my ($class, $connection, $target, $data) = @_;
	my $self = bless {}, $class;

	$self->connection($connection);
	$self->target($target);
	$self->last_id(0);

	return $self
}

sub connection { @_ > 1 ? $_[0]{table_client__connection} = $_[1] : $_[0]{table_client__connection} }
sub target { @_ > 1 ? $_[0]{table_client__target} = $_[1] : $_[0]{table_client__target} }
sub last_id { @_ > 1 ? $_[0]{table_client__last_id} = $_[1] : $_[0]{table_client__last_id} }

sub insert_async {
	my ($self, @data) = @_;

	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'query',
		target => $self->target,
		data => { type => 'insert', entries => \@data, },
	));

	$self->last_id($id);
	return $id
}

sub insert {
	my ($self, @data) = @_;
	$self->insert_async(@data);
	return $self->result
}

sub get_async {
	my ($self, %opts) = @_;

	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'query',
		target => $self->target,
		data => {
			type => 'get',
			%opts
		},
	));

	$self->last_id($id);
	return $id
}

sub get {
	my ($self, %opts) = @_;
	$self->get_async(%opts);
	return $self->result
}

sub delete_async {
	my ($self, %opts) = @_;

	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'query',
		target => $self->target,
		data => {
			type => 'delete',
			%opts
		},
	));

	$self->last_id($id);
	return $id
}

sub delete {
	my ($self, %opts) = @_;
	$self->delete_async(%opts);
	return $self->result
}

sub result {
	my ($self, $id) = @_;

	return $self->connection->read_result_id_blocking($self->last_id) unless defined $id;
	return $self->connection->read_result_id_blocking($id)
}

1;
