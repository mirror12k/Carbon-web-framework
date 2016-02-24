package Carbon::Limestone::Database;
use strict;
use warnings;


use feature 'say';


use IO::File;
use threads::shared;
use Thread::Synchronized;
use Data::Dumper;

use Carbon::Limestone::Result;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;
	# using the synchronized method functionality requires that the object be shared
	share($self); # this must be done first thing


	$self->debug($args{debug} // 0);

	$self->database_filepath($args{filepath} // die "database filepath required!");
	# $self->version(int ($args{version} // 1));

	if (not -e $self->database_filepath) {
		$self->warn(1, 'database file not found, creating new database "'.$self->database_filepath.'"');
		$self->create_database_file;
	}
	$self->open_database;


	return $self
}



sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub version { @_ > 1 ? $_[0]{limestone_database__version} = $_[1] : $_[0]{limestone_database__version} }
sub database_filepath { @_ > 1 ? $_[0]{limestone_database__database_filepath} = $_[1] : $_[0]{limestone_database__database_filepath} }



sub collections { @_ > 1 ? $_[0]{limestone_database__collections} = $_[1] : $_[0]{limestone_database__collections} }





sub warn {
	my ($self, $level, $message) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		warn "[". (caller)[0] ."]: $message\n";
	}
}



sub create_database_file {
	my ($self) = @_;
	# do nothing
}


sub open_database {
	my ($self) = @_;

	my %collections : shared;
	$self->collections(\%collections);

	$self->warn(1, "opened database file ". $self->database_filepath);
}


sub process_query {
	my ($self, $query) = @_;
	if ($query->type eq 'init') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'collection field necessary') unless defined $query->collection;

		if ($self->initialize_collection($query->collection)) {
			return Carbon::Limestone::Result->new(type => 'success');
		} else {
			return Carbon::Limestone::Result->new(type => 'error', error => 'collection already exists');
		}

	} elsif ($query->type eq 'list') {
		return Carbon::Limestone::Result->new(type => 'success', data => [$self->list_collections]);

	} elsif ($query->type eq 'append') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'collection field necessary') unless defined $query->collection;
		return Carbon::Limestone::Result->new(type => 'error', error => 'data field necessary') unless defined $query->data;
		my ($status, $data) = $self->append_collection_items($query->collection => $query->data);
		if ($status eq 'success') {
			return Carbon::Limestone::Result->new(type => 'success', data => $data);
		} else {
			return Carbon::Limestone::Result->new(type => 'error', error => $data);
		}

	} elsif ($query->type eq 'delete') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'collection field necessary') unless defined $query->collection;
		return Carbon::Limestone::Result->new(type => 'error', error => 'where clause necessary') unless defined $query->data and exists $query->data->{where};
		my ($status, $data) = $self->delete_collection_items($query->collection => $query->data);
		if ($status eq 'success') {
			return Carbon::Limestone::Result->new(type => 'success', data => $data);
		} else {
			return Carbon::Limestone::Result->new(type => 'error', error => $data);
		}

	} elsif ($query->type eq 'query') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'collection field necessary') unless defined $query->collection;
		my ($status, $data) = $self->query_collection($query->collection => $query->data);
		if ($status eq 'success') {
			return Carbon::Limestone::Result->new(type => 'success', data => $data);
		} else {
			return Carbon::Limestone::Result->new(type => 'error', error => $data);
		}

	} else {
		$self->warn(1, 'invalid query type sent by peer: "' . $query->type . '"');
		return Carbon::Limestone::Result->new(type => 'error', error => 'invalid query type: "' . $query->type . '"');
	}
}




sub append_collection_items {
	my ($self, $key, $items) = @_;
	return $self->refractor_collection($key => sub {
		my ($self, $collection) = @_;
		# $self->warn(1, 'i got the refractor_lock!');
		my $new_collection = {
			refractor_lock => $collection->{refractor_lock},
			data => [@{$collection->{data}}, @$items],
		};
		# sleep 5;
		$new_collection = shared_clone($new_collection);
		$self->get_set_collection($key => $new_collection);
		# $self->warn(1, 'releasing the refractor_lock!');
		return success => scalar @{$new_collection->{data}}
	});
}

sub delete_collection_items {
	my ($self, $key, $query) = @_;
	my $filters = $self->compile_where_filter($query->{where});
	return error => $filters unless ref $filters;

	return $self->refractor_collection($key => sub {
		my ($self, $collection) = @_;

		# get data
		my @data = @{$collection->{data}};
		my $deleted_count = @data;

		# filter it
		foreach my $filter (@$filters) {
			@data = grep $filter->($_), @data;
		}
		$deleted_count -= @data;

		# recreate the collection
		my $new_collection = {
			refractor_lock => $collection->{refractor_lock},
			data => [@data],
		};

		# put it back
		$new_collection = shared_clone($new_collection);
		$self->get_set_collection($key => $new_collection);

		# return the number of deleted items
		return success => $deleted_count
	});
}


# verified that refractor_lock works just fine
# FINALLY a solution to this mess
sub refractor_collection {
	my ($self, $key, $refraction) = @_;

	my $collection = $self->get_set_collection($key);
	return error => 'collection doesnt exist' unless defined $collection;

	# say "debug: collection: $collection, ", is_shared($collection);
	my $refractor_lock = $collection->{refractor_lock};
	# say "debug: refractor_lock: $refractor_lock, ", is_shared($refractor_lock);

	lock ($refractor_lock);
	# access it again because it could've been replaced by the time we got the lock
	my $locked_collection = $self->get_set_collection($key);
	return $refraction->($self, $locked_collection);
}

sub compile_where_filter {
	my ($self, $where) = @_;

	my @filters;
	foreach my $field (keys %$where) {
		unless ($where->{$field} =~ /\A([!=<>]=|[<>]|eq|ne)\s+(.*)\Z/) {
			return "invalid where clause: '$where->{$field}'";
		}
		my ($op, $val) = ($1, $2);
		if ($op eq '==') {
			push @filters, sub { $_->{$field} == $val };
		} elsif ($op eq '!=') {
			push @filters, sub { $_->{$field} != $val };
		} elsif ($op eq '<') {
			push @filters, sub { $_->{$field} < $val };
		} elsif ($op eq '<=') {
			push @filters, sub { $_->{$field} <= $val };
		} elsif ($op eq '>') {
			push @filters, sub { $_->{$field} > $val };
		} elsif ($op eq '>=') {
			push @filters, sub { $_->{$field} >= $val };
		} elsif ($op eq 'eq') {
			push @filters, sub { $_->{$field} eq $val };
		} elsif ($op eq 'ne') {
			push @filters, sub { $_->{$field} ne $val };
		}
	}
	return \@filters
}

sub query_collection {
	my ($self, $key, $query) = @_;

	my $collection = $self->get_set_collection($key);
	my @results = @{$collection->{data}}; # get the intial document list

	# perform any where queries on it
	if (defined $query and exists $query->{where}) {
		my $filters = $self->compile_where_filter($query->{where});
		return error => $filters unless ref $filters; # if there was a compiling error, return it
		foreach my $filter (@$filters) {
			@results = grep $filter->($_), @results;
		}
	}
	# perform any limit queries
	if (defined $query and exists $query->{limit}) {
		my $index = $query->{limit}{index};
		my $count = $query->{limit}{count};
		if (defined $index and defined $count) {
			if ($index >= 0) {
				@results = @results[ int($index) .. (int($index) + int($count) - 1) ];
			} else {
				@results = @results[ int($index) .. (int($index) + int($count) - 1) ];
			}
		} elsif (defined $index) {
			if ($index >= 0) {
				@results = @results[ int($index) .. $#results ];
			} else {
				@results = @results[ int($index) .. -1 ];
			}
		} elsif (defined $count) {
			@results = @results[ 0 .. (int($count) - 1) ];
		} else {
			return error => 'invalid limit query';
		}
	}

	# return results
	return success => \@results
}


sub initialize_collection {
	my ($self, $key) = @_;
	my $collection = $self->get_set_collection($key);
	unless (defined $collection) {
		my $new_collection = { refractor_lock => {}, data => [] };
		$new_collection = shared_clone($new_collection);
		$self->get_set_collection($key, $new_collection);
		$self->warn(1, "initialized collection $key");
		return 1
	}
	return 0
}

sub list_collections {
	my ($self) = @_;
	return keys %{$self->collections};
}


sub get_set_collection : synchronized method {
	my ($self, $key, $collection) = @_;
	if (@_ > 2) {
		if (defined $collection) {
			return $self->collections->{$key} = $collection;
		} else {
			delete $self->collections->{$key};
			return
		}
	} else {
		return $self->collections->{$key};
	}
}


1;
