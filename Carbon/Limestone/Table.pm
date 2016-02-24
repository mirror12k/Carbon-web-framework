package Carbon::Limestone::Table;
use parent 'Carbon::Limestone::DatabaseObject';
use strict;
use warnings;

use feature 'say';

use Data::Dumper;
use IO::File;
use threads::shared;
use File::Path;

use Carbon::Limestone::Result;
use Carbon::Limestone::Pack qw/ pack_value unpack_value /;




sub columns { @_ > 1 ? $_[0]{limestone_table__columns} = $_[1] : $_[0]{limestone_table__columns} }



# database object api:



sub create {
	my ($class, $filepath, $data) = @_;

	# verify that we were given columns and that they are valid
	if (not defined $data->{columns}) {
		die "columns field required in data!";
	}
	verify_columns($data->{columns});

	my $self = $class->new($filepath);

	$self->create_directory($filepath);
	$self->columns(shared_clone($data->{columns}));

	# store the new config
	my $file = IO::File->new($self->filepath . '/table_manager.db', 'w');
	my $packed = pack_value($self->columns);
	$file->print(pack 'N', length $packed);
	$file->print($packed);
	$file->close;

	say "created table: $filepath";
	say "columns: ", Dumper $self->columns;

	return $self
}


sub load {
	my ($class, $filepath) = @_;
	my $self = $class->new($filepath);

	my $data;
	my $file = IO::File->new($self->filepath . '/table_manager.db', 'r');
	$file->read($data, 4);
	my $length = unpack 'N', $data;
	$file->read($data, $length);
	$self->columns(shared_clone(unpack_value($data)));
	$file->close;


	say "loaded table: $filepath";
	say "loaded columns: ", Dumper $self->columns;

	return $self
}



sub store {
	my ($self) = @_;

	say "stored table: " . $self->filepath;
}

sub delete {
	my ($self) = @_;
	# rmdir ($self->filepath);
	rmtree($self->filepath);

	say "deleted table: " . $self->filepath;
}


sub query {
	my ($self, $query) = @_;

	say "table ", $self->filepath, " got a query: ", Dumper $query;
	return Carbon::Limestone::Result->new(type => 'success', data => 'working');
}



# other methods


my %TABLE_VALUE_TYPES = (
	INT8 => 1,
	INT16 => 2,
	INT32 => 4,
	INT64 => 8,
	UINT8 => 1,
	UINT16 => 2,
	UINT32 => 4,
	UINT64 => 8,
	BOOL => 1,
	# CHAR => 'v',
	# STRING => 'v',
);

sub verify_columns {
	my ($columns) = @_;
	die 'hash ref of columns required' unless 'HASH' eq ref $columns;
	die 'at least one column is required' unless keys %$columns;
	for my $name (keys %$columns) {
		die 'column name must not be empty' if $name eq '';
		my $type = $columns->{$name};
		die 'column type should be a string, not a ' . ref $type unless '' eq ref $type;
		die "column type '$type' is invalid" unless defined get_type_length($type);
	}
}

# returns the length in bytes of a type in table memory
sub get_type_length {
	my ($type) = @_;
	return $TABLE_VALUE_TYPES{$type} if exists $TABLE_VALUE_TYPES{$type};
	if ($type =~ /\ASTRING_(\d+)\Z/) {
		my $len = int $1;
		if ($len >= 2**32 or $len < 1) {
			die "invalid string length: $len";
		}
		if ($len < 2**8) {
			return 1 + $len
		} elsif ($len < 2**16) {
			return 2 + $len
		} else {
			return 4 + $len
		}
	} elsif ($type =~ /\ACHAR_(\d+)\Z/) {
		my $len = int $1;
		if ($len >= 2**16 or $len < 1) {
			die "invalid char array length: $len";
		}
		return $len
	}
	return undef
}






1;
