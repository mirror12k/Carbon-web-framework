package Carbon::Limestone::Table;
use parent 'Carbon::Limestone::DatabaseObject';
use strict;
use warnings;

use feature 'say';

use Carbon::Limestone::Result;
use Data::Dumper;

# a mock up of a database table

sub create {
	my ($class, $filepath, $data) = @_;
	my $self = $class->new($filepath);

	$self->create_directory($filepath);

	say "created table: $filepath";

	return $self
}


sub load {
	my ($class, $filepath) = @_;
	my $self = $class->new($filepath);

	say "loaded table: $filepath";

	return $self
}



sub store {
	my ($self) = @_;
	
	say "stored table: " . $self->filepath;
}

sub delete {
	my ($self) = @_;
	rmdir ($self->filepath);

	say "deleted table: " . $self->filepath;
}


sub query {
	my ($self, $query) = @_;

	say "table ", $self->filepath, " got a query: ", Dumper $query;
	return Carbon::Limestone::Result->new(type => 'success', data => 'working');
}


1;
