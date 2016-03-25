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

	return $self
}

sub connection { @_ > 1 ? $_[0]{table_client__connection} = $_[1] : $_[0]{table_client__connection} }
sub target { @_ > 1 ? $_[0]{table_client__target} = $_[1] : $_[0]{table_client__target} }

sub insert {
	my ($self, @data) = @_;

	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'query',
		target => $self->target,
		data => { type => 'insert', entries => \@data, },
	));

	return $id
}

sub get {
	my ($self, %opts) = @_;

	use Data::Dumper;

	say Dumper \%opts;

	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'query',
		target => $self->target,
		data => {
			type => 'get',
			%opts
		},
	));
	return $id
}

sub delete {
	my ($self, %opts) = @_;

	my $id = $self->connection->write_query(Carbon::Limestone::Query->new(
		type => 'query',
		target => $self->target,
		data => {
			type => 'delete',
			%opts
		},
	));
	return $id
}

sub result {
	my ($self, $id) = @_;
	return $self->connection->read_result_id_blocking($id)
}

1;
