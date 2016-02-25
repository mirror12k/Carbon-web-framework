package Carbon::Limestone::Table;
use parent 'Carbon::Limestone::DatabaseObject';
use strict;
use warnings;

use feature 'say';

use Data::Dumper;
use IO::File;
use threads::shared;
use File::Path;
use List::Util qw/ sum /;

use Carbon::Limestone::Result;
use Carbon::Limestone::Pack qw/ pack_value unpack_value /;




sub columns { @_ > 1 ? $_[0]{limestone_table__columns} = $_[1] : $_[0]{limestone_table__columns} }
sub table_entry_size { @_ > 1 ? $_[0]{limestone_table__table_entry_size} = $_[1] : $_[0]{limestone_table__table_entry_size} }



sub set_entry_specs {
	my ($self) = @_;

	my $offset = 1; # 1 byte for flags

	for my $col (@{$self->columns}) {
		$col->{offset} = $offset;
		$offset += $col->{length};
	}
	if ($offset % 8 != 0) {
		$offset = 8 + $offset - ($offset % 8);
	}

	$self->table_entry_size($offset);
}


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
	$self->columns(shared_clone([
		map { {
			name => $_,
			type => $data->{columns}{$_},
			length => get_type_length($data->{columns}{$_})
		} }
		keys %{$data->{columns}}
	]));
	$self->set_entry_specs;

	# store the new config
	my $file = IO::File->new($self->filepath . '/table_manager.db', 'w');
	my $packed = pack_value($self->columns);
	$file->print(pack 'N', length $packed);
	$file->print($packed);
	$file->close;

	my $entry_count = 256;
	my $entry_size = $self->table_entry_size;
	my $header_size = 5 * 8;

	my $entry_table_offset = $header_size;
	my $entry_table_size = 16 + 8 * $entry_count;

	my $entries_offset = $entry_table_offset + $entry_table_size;
	my $last_entry_offset = $entries_offset + ($entry_count - 1) * $entry_size;
	my $first_free_entry_offset = $entries_offset;

	# initialize table file
	$file = IO::File->new($self->filepath . '/table_0.ls_table', 'w');
	# entry table offset, first entry offset
	$file->print(pack 'Q<', $entry_table_offset);
	$file->print(pack 'Q<Q<Q<', $entries_offset, $last_entry_offset, $first_free_entry_offset);
	# null header terminator
	$file->print(pack 'Q<', 0);
	# entry table array size, entries in table
	$file->print(pack 'Q<Q<', $entry_count, 0);
	# table entries (initally all null)
	$file->print(pack 'Q<', 0) for 1 .. $entry_count;
	# entries (all null)
	$file->print(pack "x$entry_size") for 1 .. $entry_count;
	$file->close;


	say "created table: $filepath";
	say "columns: ", Dumper $self->columns;
	say "entry size: ", Dumper $self->table_entry_size;



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
	$self->set_entry_specs;
	$file->close;


	say "loaded table: $filepath";
	say "columns: ", Dumper $self->columns;
	say "entry size: ", Dumper $self->table_entry_size;

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
