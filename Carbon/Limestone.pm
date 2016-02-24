#!/usr/bin/env perl
package Carbon::Limestone;
use parent 'Carbon::SSL';
use strict;
use warnings;

use feature 'say';

use JSON;
use Data::Dumper;

use IO::Select;

use Carbon::Limestone::Connection;
use Carbon::Limestone::Database;


# todo:
	# add support for http only connection
	# add support for json based request and response transferring
	# user and hashed password specification in the headers
	# and make it so that it's resistant to replay attack
	# add SSL support to Carbon and move limestone over to SSL
	# add compression support to requests

	# redo the request/response system using the already inplace thread pool
		# extend the socket receive functionality
	# purge Carbon::Limestone::Database, it's unneeded
	# create a target architecture where the first name is the type, and the next is the name/namespace of it, e.g. 'Collection::TestApp::users'
		# use this target as an index into a hash with all database items in it
		# they must all implement execute_query and things like load and store


our $DEBUG_VALUE = 1 + $Carbon::CARBON_DEBUG_VALUE;

# use Fcntl ':flock';
# flock($file, LOCK_EX|LOCK_NB)

sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	$self->limestone_connections({});

	$self->open_database($args{database_filepath} // die "database_filepath not specified");

	return $self
}


sub warn {
	my ($self, $level, $message) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		warn "[". (caller)[0] ."]: $message\n";
	}
}


sub database { @_ > 1 ? $_[0]{carbon_limestone__database} = $_[1] : $_[0]{carbon_limestone__database} }
sub limestone_connections { @_ > 1 ? $_[0]{carbon_limestone__limestone_connections} = $_[1] : $_[0]{carbon_limestone__limestone_connections} }
sub limestone_selector { @_ > 1 ? $_[0]{carbon_limestone__limestone_selector} = $_[1] : $_[0]{carbon_limestone__limestone_selector} }



# hook start_server_socket to create our limestone connection selector
sub start_server_socket {
	my ($self) = @_;
	$self->SUPER::start_server_socket;
	$self->limestone_selector(IO::Select->new);
}



# hook schedule_job because instead of starting an http request processing job,
# we must quickly test if this is a proper request to start a limestone connection,
# then transform it into a limestone connection if it is
sub schedule_job {
	my ($self, $sock, $req) = @_;

	# my $jobid = $self->thread_pool->job(fileno $sock, $req);

	$self->socket_selector->remove($sock); # remove it from the selector to not read from the socket
	$self->socket_data->{"$sock"}{request} = undef; # no more request to be buffered

	if ($req->method('GET') and
			$req->uri->path eq '/' and
			'upgrade' eq lc $req->header('connection') and
			'limestone-database-connection' eq lc $req->header('upgrade') and
			defined $req->content and $req->content ne '') {

		my $data = decode_json $req->content;
		# currently we ignore completely whatever the client sends,
		# TODO: we should really analyze what it sends and set settings based on that

		my $connection = Carbon::Limestone::Connection->new;
		$connection->version(1);
		$connection->packet_length_bytes(2);
		$connection->payload_format('FreezeThaw');
		$connection->username('guest');
		$connection->socket($sock);

		my $res = Carbon::Response->new('101');
		$res->header(connection => 'upgrade');
		$res->header(upgrade => 'limestone-database-connection');
		$res->content(encode_json $connection->serialize_settings);
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'application/json');

		$sock->print($res->as_string);

		$self->limestone_connections->{"$sock"} = $connection;
		$self->limestone_selector->add($sock);
	} else {
		my $res = Carbon::Response->new('400');
		$res->content('Bad Request');
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'text/plain');

		$sock->print($res->as_string);
		return 0
	}

}



# hook update sockets to give limestone connections a chance to receive messages
sub update_sockets {
	my ($self) = @_;
	$self->SUPER::update_sockets;

	$self->update_limestone_connections;
}


# similar to update_sockets, we use a selector to find sockets that have query data for us
sub update_limestone_connections {
	my ($self) = @_;

	foreach my $sock ($self->limestone_selector->can_read(10 / 1000)) {
		my $con = $self->limestone_connections->{"$sock"};
		my $query = $con->read_query;
		if (defined $query) {
			$self->schedule_limestone_query($sock, $query);
		} elsif ($con->is_closed) {
			$self->delete_connection($con);
		}
	}
}

sub delete_connection {
	my ($self, $con) = @_;

	my $sock = $con->socket;

	$self->limestone_selector->remove($sock);
	delete $self->limestone_connections->{"$sock"};
	$self->delete_socket($sock);
}

# override update_thread_pool because we are no longer receiving http responses back
# but instead are receiving Carbon::Limestone::Result 's and sending them to limestone connections
sub update_thread_pool {
	my ($self) = @_;

	# check any thread pool jobs that have completed
	foreach my $jobid ($self->thread_pool->results) {
		say "job [$jobid] completed!"; # JOBS DEBUG
		my $sock = delete $self->socket_jobs->{$jobid};
		$sock = $self->socket_data->{"$sock"}{socket};
		my $res = $self->thread_pool->result($jobid);
		$self->limestone_connections->{"$sock"}->write_result($res // Carbon::Limestone::Result->new( type => 'error', error => 'no result' ));
		say "writing result to $sock";
	}
}



# this is where the thread_pool is now used, to parse a query
sub schedule_limestone_query {
	my ($self, $sock, $query) = @_;

	say "got query: $query";
	my $jobid = $self->thread_pool->job(fileno $sock, $query);

	$self->socket_jobs->{$jobid} = "$sock"; # record the jobid for when the job is completed

	say "job [$jobid] created!"; # JOBS DEBUG

	return $jobid
}


sub start_thread {
	my ($self, $sock_num, $query) = @_;

	return $self->serve_limestone_query($query);
}


sub serve_limestone_query {
	my ($self, $query) = @_;
	# debugging
	say "serving query $query";
	my $ret;
	eval {
		$ret = $self->database->process_query($query);
	};
	if ($@) {
		say "database query died: $@";
	}

	return $ret
	# return Carbon::Limestone::Result->new(type => 'success', data => 'working');
}



sub open_database {
	my ($self, $filepath) = @_;

	$self->database(Carbon::Limestone::Database->new(filepath => $filepath, debug => 1));
}


sub close_database {
	my ($self) = @_;
	$self->warn($DEBUG_VALUE, 'shutting down database');
	$self->database->close_database;
}


# hook cleanup so that we can store all database objects before close
sub cleanup {
	my ($self) = @_;
	$self->SUPER::cleanup;
	$self->close_database;
}




sub main {
	my $srv = Carbon::Limestone->new( debug => 1, port => 2049, database_filepath => 'test.limedb' );
	$srv->start_server;
}


caller or main(@ARGV)
