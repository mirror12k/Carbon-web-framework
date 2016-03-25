package Carbon::Limestone::Database;
use strict;
use warnings;


use feature 'say';

use JSON;
use IO::File;
use threads::shared;
use Data::Dumper;

use Carbon::Limestone::Result;
use Carbon::Limestone::Table;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;


	$self->debug($args{debug} // 0);

	$self->filepath($args{filepath} // die "database filepath required!");
	$self->version(int ($args{version} // 1));

	$self->object_types($args{object_types} // {
		%{$args{custom_object_types} // {}}, # merge the given object types with default types
		'Limestone::Table' => 'Carbon::Limestone::Table',
	});
	$self->objects(shared_clone({}));

	$self->settings({});

	unless (-e -f $self->filepath . '/limestone_settings.json') {
		$self->warn(1, 'database file not found, creating new database "'.$self->filepath.'"');
		$self->create_database;
	}
	$self->open_database;


	return $self
}



sub warn {
	my ($self, $level, $message) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		warn "[". (caller)[0] ."]: $message\n";
	}
}


sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub version { @_ > 1 ? $_[0]{limestone_database__version} = $_[1] : $_[0]{limestone_database__version} }
sub filepath { @_ > 1 ? $_[0]{limestone_database__filepath} = $_[1] : $_[0]{limestone_database__filepath} }
sub settings { @_ > 1 ? $_[0]{limestone_database__settings} = $_[1] : $_[0]{limestone_database__settings} }



sub object_types { @_ > 1 ? $_[0]{limestone_database__object_types} = $_[1] : $_[0]{limestone_database__object_types} }
sub objects { @_ > 1 ? $_[0]{limestone_database__objects} = $_[1] : $_[0]{limestone_database__objects} }




sub create_database {
	my ($self) = @_;

	# create basic databasebase settings	
	$self->settings->{objects_types} = $self->object_types;
	$self->settings->{objects} = [];

	# make the directory if it doesn't exist
	mkdir $self->filepath;

	# write them to file, they will be read by open_database
	my $file = IO::File->new($self->filepath . '/limestone_settings.json', 'w');
	$file->print(encode_json $self->settings);
	$file->close;

	# create a path for objects
	mkdir $self->filepath . '/objects/';
}


sub open_database {
	my ($self) = @_;

	$self->warn(1, "opening database ". $self->filepath);

	my $data = '';
	my $file = IO::File->new($self->filepath . '/limestone_settings.json', 'r');
	my $read = 1;
	$read = $file->read($data, 16 * 4096, length $data) while defined $read and $read > 0;
	$file->close;

	$self->settings(decode_json $data);

	$self->object_types ($self->settings->{objects_types});
	$self->load_object($_) for @{$self->settings->{objects}};
}


sub close_database {
	my ($self) = @_;

	$self->warn(1, "closing database ". $self->filepath);

	# store all database objects
	$_->store for values %{$self->objects};

	# store database settings
	$self->settings->{objects_types} = $self->object_types;
	$self->settings->{objects} = [ keys %{$self->objects} ];

	my $file = IO::File->new($self->filepath . '/limestone_settings.json', 'w');
	$file->print(encode_json $self->settings);
	$file->close;

}


sub process_query {
	my ($self, $query) = @_;

	return Carbon::Limestone::Result->new(type => 'error', error => 'type field necessary') unless defined $query->type;

	if ($query->type eq 'create') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'target field necessary') unless defined $query->target;

		my $status = $self->create_object($query->target, $query->data);
		if ($status eq 'success') {
			return Carbon::Limestone::Result->new(type => 'success');
		} else {
			return Carbon::Limestone::Result->new(type => 'error', error => $status);
		}

	} elsif ($query->type eq 'delete') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'target field necessary') unless defined $query->target;

		my $status = $self->delete_object($query->target);
		if ($status eq 'success') {
			return Carbon::Limestone::Result->new(type => 'success');
		} else {
			return Carbon::Limestone::Result->new(type => 'error', error => $status);
		}

	} elsif ($query->type eq 'list') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'target field necessary') unless defined $query->target;
		return Carbon::Limestone::Result->new(type => 'success', data => [$self->list_objects($query->target)]);

	} elsif ($query->type eq 'query') {
		return Carbon::Limestone::Result->new(type => 'error', error => 'target field necessary') unless defined $query->target;
		return $self->query_object($query);

	} else {
		$self->warn(1, 'invalid query type sent by peer: "' . $query->type . '"');
		return Carbon::Limestone::Result->new(type => 'error', error => 'invalid query type: "' . $query->type . '"');
	}
}

sub create_object {
	my ($self, $path, $data) = @_;

	my ($objtype, $filepath) = split '=', $path, 2;
	$filepath =~ s/::/\//g;
	$filepath = $self->filepath . '/objects/' . $filepath;

	return $self->lock_objects (sub {
		return 'object already exists' if exists $self->objects->{$path};
		my $obj = $self->object_types->{$objtype}->create($filepath, $data);
		if (defined $obj) {
			$self->objects->{$path} = $obj;
			return 'success'
		} else {
			return 'failed to create object';
		}
	});
}

sub load_object {
	my ($self, $path) = @_;

	my ($objtype, $filepath) = split '=', $path, 2;
	$filepath =~ s/::/\//g;
	$filepath = $self->filepath . '/objects/' . $filepath;

	return $self->lock_objects (sub {
		my $obj = $self->object_types->{$objtype}->load($filepath);
		$self->objects->{$path} = $obj if defined $obj;
		return $obj
	});
}

sub delete_object {
	my ($self, $path) = @_;

	# grab the object while quickly removing it from the objects list
	my $object = $self->lock_objects (sub { delete $self->objects->{$path} });

	if (defined $object) {
		$object->delete;
		return 'success'
	} else {
		return 'object does not exist';
	}
}

sub list_objects {
	my ($self, $name) = @_;

	my $regex = quotemeta $name;
	$regex =~ s/\\\*/.*/gms;
	my @objects = $self->lock_objects (sub { keys %{$self->objects} });

	return grep $_ =~ /\A$regex\Z/ms, @objects
}


sub query_object {
	my ($self, $query) = @_;
	my $path = $query->target;

	# lock to get the object to make sure no collisions with other operations occurs
	my $object = $self->lock_objects (sub { $self->objects->{$path} });
	return Carbon::Limestone::Result->new(type => 'error', error => 'object does not exist') unless defined $object;

	# perform the query
	return $object->query($query);
}


sub lock_objects {
	my ($self, $fun) = @_;
	my $objects = $self->objects;
	lock($objects);
	return $fun->();
}


1;
