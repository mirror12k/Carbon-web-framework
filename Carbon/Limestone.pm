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


# TODO:
	# add support for http only connection
	# add support for json based request and response transferring
	# add support for limestone-pack based request and response transferring
	# make limestone-pack pack hashes in sorted key order for efficient compression
	# user and hashed password specification in the headers
	# add compression support to requests

	# TODO with table:
		# multiple parallel files allow reading while writing
		# allow writing of entries while still reading
			# just needs a synchronized memory entry manager
			# and a synchronized entries table
			# would allow parallelized inserting and deleting of entries with only the memory manager and the synchro'd memory table as bottlenecks
		# clean up the code
		# compiled database operations?
		# dynamic size entries to allow true HUGE strings
			# can add a flag to entries which indicates an expanded memory entry
			# expanded memory entry gobbles up memory entries after it (they must be free of course)
			# if the extended flag is present, then the next <something> int will indicate how many memory entries it has taken
			# this will allow true huge strings
		# indexes
			# probably a binary tree with pointers into the entries table
			# branch format:
				# qword - pointer to comparison value
				# qword - a [branch|entry] pointer to values less than or equal to the comparison value
				# qword - a [branch|entry] pointer to values greater than the comparison value
			# branches would be stored in normal entry slots
		# is there a better way than opening the file everytime?
		# should inserts and deletions be queued up and then performed in one swoop?
			# create a thread queue of size X, when an insert or deletion with a LOW_PRIORITY flag happens:
				# if the queue has less than X elements, the query is simply appended to the queue
				# if the queue has X number of elements, the queue is dumped and all queries in the queue are blobed together and executed all at once
				# if the database has a few milliseconds of no queries, it will start a process to perform the queued operations
			# could get's be queued up for low priority?
			# what would the return value be? or would there now be a return value with low priority



our $DEBUG_VALUE = 1 + $Carbon::CARBON_DEBUG_VALUE;

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
			defined $req->content and $req->content ne '') { # verify that the peer is requesting a limestone connection

		my $data = decode_json $req->content;
		# currently we ignore completely whatever the client sends,
		# TODO: we should really analyze what it sends and set settings based on that

		# say "data: ", Dumper $data;

		if (exists $data->{username} and exists $data->{password} and defined $data->{username} and defined $data->{password} and
				$self->database->verify_login($data->{username}, $data->{password})) { # verify the login

			my $connection = Carbon::Limestone::Connection->new;
			$connection->version(1);
			$connection->packet_length_bytes(2);
			$connection->payload_format('FreezeThaw');
			$connection->username($data->{username});
			$connection->socket($sock);

			my $res = Carbon::Response->new('101');
			$res->header(connection => 'upgrade');
			$res->header(upgrade => 'limestone-database-connection');
			$res->content(encode_json $connection->serialize_settings);
			$res->header('content-length' => length $res->content);
			$res->header('content-type' => 'application/json');


			$self->limestone_connections->{"$sock"} = $connection;
			$self->limestone_selector->add($sock);

			$sock->print($res->as_string);
			return 1
		} else { # incorrect password
			my $res = Carbon::Response->new('401');
			$res->content('Bad Login');
			$res->header('content-length' => length $res->content);
			$res->header('content-type' => 'text/plain');

			$sock->print($res->as_string);
			return 0
		}
	} else { # not a limestone connection request
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
			
			while ($query = $con->read_query){
				# say "reading from $sock"; # CON DEBUG
				$self->schedule_limestone_query($sock, $query);
			}
		} elsif ($con->last_read == 0) {
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
		$self->warn($DEBUG_VALUE, "job [$jobid] completed!"); # JOBS DEBUG
		my $res = $self->thread_pool->result($jobid);
		my $sock = delete $self->socket_jobs->{$jobid};
		$sock = $self->socket_data->{"$sock"}{socket};
		if (defined $sock) {
			$self->limestone_connections->{"$sock"}->write_result(
				$res // Carbon::Limestone::Result->new( type => 'error', error => 'database generated no result' ));
			# say "writing result to $sock"; # CON DEBUG
		}
		#  else { say "socket closed before a write could be completed"; } # CON DEBUG
	}
}



# this is where the thread_pool is now used, to parse a query
sub schedule_limestone_query {
	my ($self, $sock, $query) = @_;

	# say "got query: $query"; # CON DEBUG
	my $jobid = $self->thread_pool->job(fileno $sock, $query);

	$self->socket_jobs->{$jobid} = "$sock"; # record the jobid for when the job is completed

	$self->warn($DEBUG_VALUE, "job [$jobid] created!"); # JOBS DEBUG

	return $jobid
}


sub start_thread {
	my ($self, $sock_num, $query) = @_;

	return $self->serve_limestone_query($query);
}


sub serve_limestone_query {
	my ($self, $query) = @_;
	
	# say "serving query $query"; # CON DEBUG
	my $ret;
	eval {
		$ret = $self->database->process_query($query);
	};
	if ($@) {
		$self->warn ($DEBUG_VALUE, "worker thread died: $@");
		$ret = Carbon::Limestone::Result->new(type => 'error', error => "worker thread died: $@");
	}

	return $ret
}



sub open_database {
	my ($self, $filepath) = @_;

	$self->database(Carbon::Limestone::Database->new(filepath => $filepath));
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
