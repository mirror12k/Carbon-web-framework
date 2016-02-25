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
use Thread::Semaphore;

use Carbon::Limestone::Result;
use Carbon::Limestone::Pack qw/ pack_value unpack_value /;




sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->table_reference_semaphore(Thread::Semaphore->new);
	$self->table_access_lock(shared_clone({}));

	return $self
}


sub columns { @_ > 1 ? $_[0]{limestone_table__columns} = $_[1] : $_[0]{limestone_table__columns} }
sub table_entry_size { @_ > 1 ? $_[0]{limestone_table__table_entry_size} = $_[1] : $_[0]{limestone_table__table_entry_size} }
sub table_reference_semaphore { @_ > 1 ? $_[0]{limestone_table__table_reference_semaphore} = $_[1] : $_[0]{limestone_table__table_reference_semaphore} }
sub table_access_lock { @_ > 1 ? $_[0]{limestone_table__table_access_lock} = $_[1] : $_[0]{limestone_table__table_access_lock} }



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

	# since we verified that the data is valid, we can start actually creating the table
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

	# varous values for table file
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
	my $data = $query->data // return Carbon::Limestone::Result->new(type => 'error', error => 'data field required');
	# say "table ", $self->filepath, " got a query: ", Dumper $query;

	if ($data->{type} eq 'insert') {
		my $count = $self->edit_table(
			\&insert_entry,
			[ map $self->pack_entry($_), @{$data->{entries}} ], # pre-pack the entry so that we aren't doing it in locked context
		);
		# insert returns the current number of entries in the table
		return Carbon::Limestone::Result->new(type => 'success', data => $count);
	} elsif ($data->{type} eq 'get') {
		$self->access_table(sub {
			say "getting values out of a table!";
			sleep 3;
			say "done getting!";
		});
	} else {
		Carbon::Limestone::Result->new(type => 'error', error => "unknown table query type '$data->{type}'")
	}

	return Carbon::Limestone::Result->new(type => 'success', data => 'working');
}



# primary synchronization methods


# any function passed to access_table is ensured that no changes will be made to the database file for the duration of its operation
# however multiple table-accessing operations can happen in parallel, so the subroutine must not edit the file itself
sub access_table {
	my $self = shift;
	my $fun = shift;

	$self->increment_table_reference_count;
	my @ret = $fun->($self, @_);
	$self->decrement_table_reference_count;
	return @ret if wantarray;
	return $ret[0]
}

# any function passed to edit_table is ensured that no other subroutine is/can access or edit the table for the duration of its operation
sub edit_table {
	my $self = shift;
	my $fun = shift;

	my $access_lock = $self->table_access_lock;
	lock($access_lock);
	$self->table_reference_semaphore->down;
	my @ret = $fun->($self, @_);
	$self->table_reference_semaphore->up;
	return @ret if wantarray;
	return $ret[0]
}

# this is just to scope the lock
sub increment_table_reference_count {
	my ($self) = @_;
	my $access_lock = $self->table_access_lock;
	lock($access_lock);
	$self->table_reference_semaphore->down_force;
	# lock is freed at the end of this function	
}

sub decrement_table_reference_count {
	my ($self) = @_;
	$self->table_reference_semaphore->up;
}

use Fcntl;
sub insert_entry {
	my ($self, $entries) = @_;
	# entries are already packed to prevent wasting cpu in locked context
	
	my @to_insert = @$entries;
	my @inserted_addresses;

	# open the table file
	my $file = IO::File->new($self->filepath . '/table_0.ls_table', 'r+');
	$file->read(my $buf, 8 * 2);
	my ($table_offset, $first_entry_offset) = unpack 'Q<Q<', $buf;

	# insert data into free entries
	$file->seek($first_entry_offset, SEEK_SET);
	while (@to_insert) {
		$file->read($buf, 1);
		my $taken = 0x1 & ord $buf;
		if ($taken) {
			$file->seek($self->table_entry_size - 1, SEEK_CUR);
		} else {
			$file->seek(-1, SEEK_CUR);
			push @inserted_addresses, $file->tell;
			$file->print("\x01" . shift @to_insert);
		}
	}
	
	# go the the entries table
	$file->seek($table_offset, SEEK_SET);
	$file->read($buf, 16);
	my ($table_length, $current_entries) = unpack 'Q<Q<', $buf;
	say "debug table length: $table_length, entries: $current_entries";
	# first write the new entries count
	$file->seek(-8, SEEK_CUR);
	$file->print(pack 'Q<', $current_entries + @inserted_addresses);

	$file->seek($current_entries * 8, SEEK_CUR); # seek to end of table
	# now write the addresses into the entries table
	for my $addr (@inserted_addresses) {
		$file->print(pack 'Q<', $addr);
	}

	$file->close;

	return $current_entries + @inserted_addresses
}



# utility methods


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


# packs the column values as stored in the table
# pads with nulls to full entry size - 1
# does not pack the flags byte
sub pack_entry {
	my ($self, $data) = @_;

	my $res = '';
	for my $col (@{$self->columns}) {
		if ($col->{type} eq 'UINT64') {
			$res .= pack 'Q<', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'UINT32') {
			$res .= pack 'L<', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'UINT16') {
			$res .= pack 'S<', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'UINT8') {
			$res .= pack 'C', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'INT64') {
			$res .= pack 'q<', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'INT32') {
			$res .= pack 'l<', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'INT16') {
			$res .= pack 's<', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'INT8') {
			$res .= pack 'c', $data->{$col->{name}} // 0;
		} elsif ($col->{type} eq 'BOOL') {
			$res .= pack 'C', $data->{$col->{name}} // 0;
		} elsif ($col->{type} =~ /\ACHAR_(\d+)\Z/) {
			my $len = int $1;
			my $s = $data->{$col->{name}} // '';
			$s = substr $s, 0, $len if $len < length $s;
			$s .= "\0" x ($len - length $s);
			$res .= $s;
		} elsif ($col->{type} =~ /\ASTRING_(\d+)\Z/) {
			my $len = int $1;
			my $s = $data->{$col->{name}} // '';
			$s = substr $s, 0, $len if $len < length $s;

			if ($len < 2**8) {
				$res .= pack 'C', length $s;
			} elsif ($len < 2**16) {
				$res .= pack 'S', length $s;
			} else {
				$res .= pack 'L', length $s;
			}

			$s .= "\0" x ($len - length $s);
			$res .= $s;
		} else {
			die "unknown size to pack: $col->{type}";
		}
	}

	my $padding = $self->table_entry_size - length($res) - 1;
	$res .= pack "x$padding";

	return $res
}




1;
