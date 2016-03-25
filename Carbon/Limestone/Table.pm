package Carbon::Limestone::Table;
use parent 'Carbon::Limestone::DatabaseObject';
use strict;
use warnings;

use feature 'say';

use IO::File;
use File::Path;
use Fcntl;
use List::Util qw/ sum none /;
use threads::shared;
use Thread::Semaphore;

use Carbon::Limestone::Result;
use Carbon::Limestone::Pack qw/ pack_value unpack_value /;

use Data::Dumper;



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
	my $entry_count = 8;
	my $entry_size = $self->table_entry_size;
	my $header_size = $self->table_header_length;

	my $entry_table_offset = $header_size;
	my $entry_table_size = 8 * $entry_count;

	my $entries_offset = $entry_table_offset + $entry_table_size;
	my $last_entry_offset = $entries_offset + ($entry_count - 1) * $entry_size;
	my $first_free_entry_offset = $entries_offset;

	# initialize table file
	$file = IO::File->new($self->filepath . '/table_0.ls_table', 'w');

	$self->write_table_header($file, {
		entry_table_offset => $entry_table_offset,
		first_entry_offset => $entries_offset,
		last_entry_offset => $last_entry_offset,
		first_free_entry_offset => $first_free_entry_offset,
		entry_count => $entry_count,
		used_entry_count => 0,
	}, 1);

	# # entry table array size, entries in table
	# $file->print(pack 'Q<Q<', $entry_count, 0);
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
			\&insert_entries,
			[ map $self->pack_entry($_), @{$data->{entries}} ], # pre-pack the entry so that we aren't doing it in locked context
		);
		# insert returns the current number of entries in the table
		return Carbon::Limestone::Result->new(type => 'success', data => $count);
	} elsif ($data->{type} eq 'get') {
		my $entries = $self->access_table(\&get_entries, $data);
		return Carbon::Limestone::Result->new(type => 'success', data => $entries);
	} elsif ($data->{type} eq 'delete') {
		my $count = $self->edit_table(\&delete_entries, $data);
		return Carbon::Limestone::Result->new(type => 'success', data => $count);
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


# primary editting operations:

sub table_header_length { 7 * 8 }

sub write_table_header {
	my ($self, $file, $data, $noseek) = @_;


	$file->seek(0, SEEK_SET) unless $noseek;

	$data = pack 'Q<Q<Q<Q<Q<Q<Q<',
		$data->{entry_table_offset},
		$data->{first_entry_offset}, $data->{last_entry_offset}, $data->{first_free_entry_offset},
		$data->{entry_count}, $data->{used_entry_count},
		0; # null header terminator

	$file->print($data);
}

sub read_table_header {
	my ($self, $file, $noseek) = @_;

	$file->seek(0, SEEK_SET) unless $noseek;

	$file->read(my $buf, $self->table_header_length);

	my %data;
	@data{qw/ entry_table_offset
		first_entry_offset last_entry_offset first_free_entry_offset
		entry_count used_entry_count /} = unpack 'Q<Q<Q<Q<Q<Q<', $buf;

	return \%data
}

sub expand_table_file {
	my ($self, $file, $header) = @_;

	my $additional_entries = $header->{entry_count};

	# calculate how many entry slots will be displaced
	my $new_entry_table_memory = 8 * $header->{entry_count} + 8 * $additional_entries;

	# say " $new_entry_table_memory - ($header->{first_entry_offset} - $header->{entry_table_offset}) ";
	my $entries_reposessed = $new_entry_table_memory - ($header->{first_entry_offset} - $header->{entry_table_offset});
	$entries_reposessed /= $self->table_entry_size;
	$entries_reposessed = 1 + int $entries_reposessed if $entries_reposessed != int $entries_reposessed;

	# say "entries_reposessed: $entries_reposessed";

	# read the displaced entries
	$file->seek($header->{first_entry_offset}, SEEK_SET);
	$file->read(my $moved_entries, $entries_reposessed * $self->table_entry_size);

	# null the new entry table values
	$file->seek($header->{entry_table_offset} + $additional_entries * 8, SEEK_SET);
	$file->print(pack 'Q<', 0) for 1 .. $additional_entries;

	# get a mapping of relocated offsets
	my %relocated_offsets = map {
		$header->{first_entry_offset} + $_ * $self->table_entry_size => $header->{last_entry_offset} + ($_ + 1) * $self->table_entry_size
	} 0 .. ($entries_reposessed - 1);

	# set the new first entry pointer
	$header->{first_entry_offset} = $header->{first_entry_offset} + $entries_reposessed * $self->table_entry_size;

	# write the displaced entries to the end
	# say "adding ", length($moved_entries), " bytes at offset ", $header->{last_entry_offset} + $self->table_entry_size;
	$file->seek($header->{last_entry_offset} + $self->table_entry_size, SEEK_SET);
	$file->print($moved_entries);

	# write null entries to the new entry slots
	# say "adding ", $additional_entries * $self->table_entry_size, " bytes at offset ", $file->tell;
	my $null_entry = "\0" x $self->table_entry_size;
	$file->print($null_entry) for 1 .. $additional_entries;

	# set the new last entry pointer
	$header->{last_entry_offset} = $header->{last_entry_offset} + $self->table_entry_size * $additional_entries + length $moved_entries;

	# go to the start of the entry table
	$file->seek($header->{entry_table_offset}, SEEK_SET);
	$file->read(my $buf, 8);
	my $pointer = unpack 'Q<', $buf;
	while ($pointer != 0) {
		if (exists $relocated_offsets{$pointer}) {
			# say "relocated pointer $pointer";
			$file->seek(-8, SEEK_CUR);
			$file->print(pack 'Q<', $relocated_offsets{$pointer});
		}
		$file->read($buf, 8);
		$pointer = unpack 'Q<', $buf;
	}

	$header->{entry_count} += $additional_entries;

	# write changes to header to file
	$self->write_table_header($file, $header);
}


sub insert_entries {
	my ($self, $entries) = @_;
	# entries are already packed to prevent wasting cpu in locked context
	
	my @to_insert = @$entries;
	my @inserted_addresses;

	# open the table file
	my $file = IO::File->new($self->filepath . '/table_0.ls_table', 'r+');

	my $header = $self->read_table_header($file, 1);

	my $loop = 0;
	# say "debug: $header->{entry_count} < $header->{used_entry_count} + ", scalar @to_insert;
	while ($header->{entry_count} < $header->{used_entry_count} + @to_insert) {
		$self->expand_table_file($file, $header);
		die "loop $loop" if $loop++ > 5;
	}

	# insert data into free entries
	$file->seek($header->{first_entry_offset}, SEEK_SET);
	my $offset = $header->{first_entry_offset};
	while (@to_insert and $offset <= $header->{last_entry_offset}) {
		$file->read(my $buf, 1);
		my $taken = 0x1 & ord $buf;
		if ($taken) {
			$file->seek($self->table_entry_size - 1, SEEK_CUR);
		} else {
			$file->seek(-1, SEEK_CUR);
			push @inserted_addresses, $file->tell;
			$file->print("\x01" . shift @to_insert);
		}
		$offset += $self->table_entry_size;
	}

	# if we still have entries, it means we've reached the end of the table
	die "corrupt table: reached end of table but still have ", scalar (@to_insert), " entries to write" if @to_insert;
	
	# go the the entries table
	# $file->seek($header->{entry_table_offset}, SEEK_SET);
	# $file->read(my $buf, 16);
	# my ($table_length, $current_entries) = unpack 'Q<Q<', $buf;
	# say "debug table length: $table_length, entries: $current_entries";
	# first write the new entries count
	# $file->seek(-8, SEEK_CUR);
	# $file->print(pack 'Q<', $current_entries + @inserted_addresses);

	$file->seek($header->{entry_table_offset} + $header->{used_entry_count} * 8, SEEK_SET); # seek to end of table
	# now write the addresses into the entries table
	for my $addr (@inserted_addresses) {
		$file->print(pack 'Q<', $addr);
	}


	$header->{used_entry_count} += @$entries;
	$self->write_table_header($file, $header);

	$file->close;

	return $header->{used_entry_count}
}


sub delete_entries {
	my ($self, $query) = @_;

	my $where_filter;
	$where_filter = $self->compile_where_filter($query->{where}) if defined $query->{where};
	my $entry_size = $self->table_entry_size;

	# open the table file
	my $file = IO::File->new($self->filepath . '/table_0.ls_table', 'r+');

	my $header = $self->read_table_header($file, 1);

	my $buf;

	# # go to the entries table
	# $file->read($buf, 16);
	# my (undef, $current_entries) = unpack 'Q<Q<', $buf;

	# iterate through the entries and find entries to delete
	my $current_offset = $header->{entry_table_offset};
	my @deleted_offsets;
	my @deleted_entries;

	$file->seek($header->{entry_table_offset}, SEEK_SET);
	for (1 .. $header->{used_entry_count}) { # iterate entries table
		# get the entry address
		$file->read($buf, 8);
		$current_offset += 8;
		my $entry_addr = unpack 'Q<', $buf;

		# read the entry and parse it
		$file->seek($entry_addr, SEEK_SET);
		$file->read($buf, $entry_size);
		my $entry = $self->unpack_entry($buf);

		# filter it if we have a filter, and delete it
		unless (defined $where_filter and not $where_filter->($entry)) {
			# say "found entry $entry_addr to delete (table offset: ", $current_offset - 8, ")";
			push @deleted_offsets, $current_offset - 8;
			push @deleted_entries, $entry_addr;
		}
		# go back to entries table
		$file->seek($current_offset, SEEK_SET);


		# this can probably be optimized by reading multiple offsets at once and then jumping around to read them
	}

	my $delete_count = @deleted_offsets;

	# now take all entries that we need to delete and clear their taken flag
	for my $addr (@deleted_entries) {
		# say "deleted entry $addr";
		$file->seek($addr, SEEK_SET);
		$file->print("\0"); # just write a null byte to its flags
	}

	# now we need to find replacement entries to consolidate the entries table
	my @replacement_entries;
	$current_offset = $header->{entry_table_offset} + 8 * $header->{used_entry_count} - 8;
	my $last_offset = $current_offset - 8 * $delete_count;
	while ($current_offset > $last_offset and @replacement_entries < $delete_count) {
		if (none { $current_offset == $_ } @deleted_offsets) { # make sure that the replacement isn't one that we are deleting
			# TODO: can optimize this down to only 1 comparison
			$file->seek($current_offset, SEEK_SET);
			$file->read($buf, 8);
			# say "found replacement entry $current_offset";
			push @replacement_entries, unpack 'Q<', $buf;
		}
		$current_offset -= 8;
	}

	# now we replace deleted entries with the found replacements
	for my $replacement (@replacement_entries) {
		my $offset = shift(@deleted_offsets);
		# say "replacing entry at offset $offset";
		$file->seek($offset, SEEK_SET);
		$file->print(pack 'Q<', $replacement);
	}

	# if we didn't have enough replacement entries, that's completely fine
	# since the deleted offsets are in order, we have replaced any deleted ones at the front already
	# the back ones will be ignored because we edit the number of current entries to exclude them

	# # write the new number of entries to the entry table
	# $file->seek($header->{entry_table_offset} + 8, SEEK_SET);
	# # say "deleted $delete_count entries";
	# $file->print(pack 'Q<', $current_entries - $delete_count);


	$header->{used_entry_count} -= $delete_count;
	$self->write_table_header($file, $header);

	$file->close;

	# return the count of deleted entries
	return $delete_count
}



# TODO: sanitize this
sub compile_where_filter {
	my ($self, $where) = @_;

	my @code;
	foreach my $field (keys %$where) {
		unless ($where->{$field} =~ /\A([!=<>]=|[<>]|eq|ne)\s+(.*)\Z/) {
			return "invalid where clause: '$where->{$field}'";
		}
		my ($op, $val) = ($1, $2);
		if ($op eq '==') {
			push @code, "\$entry->{'$field'} == $val";
		} elsif ($op eq '!=') {
			push @code, "\$entry->{'$field'} != $val";
		} elsif ($op eq '<') {
			push @code, "\$entry->{'$field'} < $val";
		} elsif ($op eq '<=') {
			push @code, "\$entry->{'$field'} <= $val";
		} elsif ($op eq '>') {
			push @code, "\$entry->{'$field'} > $val";
		} elsif ($op eq '>=') {
			push @code, "\$entry->{$field} >= $val";
		} elsif ($op eq 'eq') {
			push @code, "\$entry->{$field} eq $val";
		} elsif ($op eq 'ne') {
			push @code, "\$entry->{$field} ne $val";
		}
	}
	my $code = join ' and ', @code;
	$code = "sub { my \$entry = shift; $code }";
	# say "compiling where filter: $code";
	return eval $code
}



sub get_entries {
	my ($self, $query) = @_;

	# some setup
	my @results;
	my $where_filter;
	$where_filter = $self->compile_where_filter($query->{where}) if defined $query->{where};
	my $entry_size = $self->table_entry_size;


	# open the file and read the table pointer
	my $file = IO::File->new($self->filepath . '/table_0.ls_table', 'r+');

	my $header = $self->read_table_header($file, 1);

	# $file->read(my $buf, 8);
	# my ($table_offset) = unpack 'Q<', $buf;

	# # go to the entries table
	# $file->seek($header->{entry_table_offset}, SEEK_SET);
	# $file->read(my $buf, 16);
	# my (undef, $current_entries) = unpack 'Q<Q<', $buf;

	my $current_offset = $header->{entry_table_offset};
	$file->seek($header->{entry_table_offset}, SEEK_SET);
	for (1 .. $header->{used_entry_count}) { # iterate entries table
		# get the entry address
		$file->read(my $buf, 8);
		$current_offset += 8;
		my $entry_addr = unpack 'Q<', $buf;

		# read the entry and parse it
		$file->seek($entry_addr, SEEK_SET);
		$file->read($buf, $entry_size);
		my $entry = $self->unpack_entry($buf);
		# filter it if we have a filter, and add it to the results
		unless (defined $where_filter and not $where_filter->($entry)) {
			push @results, $entry;
		}

		# go back to entries table
		$file->seek($current_offset, SEEK_SET);

		# this can probably be optimized by reading multiple offsets at once and then jumping around to read them
	}
	$file->close;

	return \@results
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
			$res .= pack 'C', 0x1 & ($data->{$col->{name}} // 0);
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
				$res .= pack 'S<', length $s;
			} else {
				$res .= pack 'L<', length $s;
			}

			$s .= "\0" x ($len - length $s);
			$res .= $s;
		} else {
			die "unknown value to pack: $col->{type}";
		}
	}

	my $padding = $self->table_entry_size - length($res) - 1;
	$res .= pack "x$padding";

	return $res
}


sub unpack_entry {
	my ($self, $entry) = @_;

	my $res = {};

	for my $col (@{$self->columns}) {
		if ($col->{type} eq 'UINT64') {
			$res->{$col->{name}} = unpack 'Q<', substr $entry, $col->{offset}, 8;
		} elsif ($col->{type} eq 'UINT32') {
			$res->{$col->{name}} = unpack 'L<', substr $entry, $col->{offset}, 4;
		} elsif ($col->{type} eq 'UINT16') {
			$res->{$col->{name}} = unpack 'S<', substr $entry, $col->{offset}, 2;
		} elsif ($col->{type} eq 'UINT8') {
			$res->{$col->{name}} = unpack 'C', substr $entry, $col->{offset}, 1;
		} elsif ($col->{type} eq 'INT64') {
			$res->{$col->{name}} = unpack 'q<', substr $entry, $col->{offset}, 8;
		} elsif ($col->{type} eq 'INT32') {
			$res->{$col->{name}} = unpack 'l<', substr $entry, $col->{offset}, 4;
		} elsif ($col->{type} eq 'INT16') {
			$res->{$col->{name}} = unpack 's<', substr $entry, $col->{offset}, 2;
		} elsif ($col->{type} eq 'INT8') {
			$res->{$col->{name}} = unpack 'c', substr $entry, $col->{offset}, 1;
		} elsif ($col->{type} eq 'BOOL') {
			$res->{$col->{name}} = unpack 'C', substr $entry, $col->{offset}, 1;
		} elsif ($col->{type} =~ /\ACHAR_(\d+)\Z/) {
			$res->{$col->{name}} = substr $entry, $col->{offset}, 1;
		} elsif ($col->{type} =~ /\ASTRING_(\d+)\Z/) {
			my $len = int $1;
			if ($len < 2**8) {
				my $slen = unpack 'C', substr $entry, $col->{offset}, 1;
				$res->{$col->{name}} = substr $entry, $col->{offset} + 1, $slen;
			} elsif ($len < 2**16) {
				my $slen = unpack 'S<', substr $entry, $col->{offset}, 2;
				$res->{$col->{name}} = substr $entry, $col->{offset} + 2, $slen;
			} else {
				my $slen = unpack 'L<', substr $entry, $col->{offset}, 4;
				$res->{$col->{name}} = substr $entry, $col->{offset} + 4, $slen;
			}
		} else {
			die "unknown value to pack: $col->{type}";
		}
	}

	return $res
}




1;
