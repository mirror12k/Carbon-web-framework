package Carbon::Limestone::DatabaseObject;
use strict;
use warnings;

use feature 'say';
use threads::shared;


# provides a base class for database objects with a few convenient methods


sub new {
	my ($class, $filepath) = @_;
	my $self = bless {}, $class;
	share($self);

	$self->filepath($filepath);

	return $self
}

sub filepath { @_ > 1 ? $_[0]{limestone_databaseobject__filepath} = $_[1] : $_[0]{limestone_databaseobject__filepath} }


sub create_directory {
	my ($self, $filepath) = @_;
	mkdir $filepath;
}



1;
