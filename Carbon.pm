package Carbon;

use strict;
use warnings;

use feature 'say';


use Carp;
use IO::Socket::INET;
use IO::Select;
use Thread::Pool;
use Time::HiRes 'usleep';

# use HTTP::Request;
# use HTTP::Response;

use Carbon::URI;
use Carbon::Request;
use Carbon::Response;



=pod

=head1 What is Carbon?

Carbon is a flexible and easily extendable http server architecture

using IO::Select, it is resistent to typical denial of service via the slow-loris attack
Thread::Pool ensures that requests are completed quickly and in parallel

Carbon abstracts away any necessary network layer functionality so that a router can focus on the http details
comes with the routers Carbon::Fiber and Carbon::Nanotube, however anyone can implement their own router with just a few methods

Carbon::Fiber acts as a general router with regex-routing to functions, directories, and route mapping
Carbon::Nanotube provides bindings for dynamic file compilation and execution for a fully functional web-stack
comes with Anthracite which acts as a compiler and a runtime for dynamic files invoked by Carbon::Nanotube
and allows plugins such as Limestone to provide additional functionality

=head2 prerequisites

Carp
IO::Socket::INET
IO::Select
Thread::Pool
Time::HiRes

=cut




# TODO:
# caching data
# route shortcutting
# route excluding

# graphite plugin for anthracite
	# graphite runtime variable
	# graphite template compilation
# sql database plugin for anthracite
# FastCGI runtime?
# MIME type -based content-type setting
# cookies and sessions
# a security suite:
	# password hashing
	# natural csrf tokens
	# session tokens


# awesome names to use:

# methane, oil, coal
# charcoal
# coalmine
# carbide
# carbon14
# hydrocarbon

# fiber -> routing engine
# nanotube -> dynamic file routing engine
# anthracite -> dynamic file compiler and runtime
# graphite -> templating engine
# graphene

# carbon aerogel
# carbon fibre-reinforced carbon ( aka space carbon )

# diamond

# limestone -> document database engine
# fossiliferous limestone
# coral
# chalk

# dolomite
# calcite
# azurite
# malachite




our $CARBON_DEBUG_VALUE = 1;

=item new()
initializes a new Carbon server

options:
debug => debug level
port => server port
onerror => subroutine to call when $server->die is called

=cut
sub new ($%) {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->debug($args{debug} // 0);

	$self->port($args{port} // 2048);
	$self->onerror($args{onerror} // \&Carp::croak);

	$self->server_running(0);
	$self->socket_data({});
	$self->socket_jobs({});

	return $self
}

sub warn {
	my ($self, $level, $message) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		warn "[". (caller)[0] ."]: $message\n";
	}
}

sub die {
	my $self = shift;
	$self->onerror->("[$self] ", @_);
	CORE::die "returning from onerror is not allowed";
}

=item debug
get/set the debug level
level 0 means no output
level 1 produces output from the Carbon package and subclasses
=cut
sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }

=item server_running
whether the server is currently running
=cut
sub server_running { @_ > 1 ? $_[0]{carbon_server__running} = $_[1] : $_[0]{carbon_server__running} }

=item port
the port the server is (going to) run on
=cut
sub port { @_ > 1 ? $_[0]{carbon_server__port} = $_[1] : $_[0]{carbon_server__port} }
sub server_socket { @_ > 1 ? $_[0]{carbon_server__server_socket} = $_[1] : $_[0]{carbon_server__server_socket} }
sub socket_selector { @_ > 1 ? $_[0]{carbon_server__socket_selector} = $_[1] : $_[0]{carbon_server__socket_selector} }
# temporary socket data storage
sub socket_data { @_ > 1 ? $_[0]{carbon_server__socket_data} = $_[1] : $_[0]{carbon_server__socket_data} }
# temporary job information storage
sub socket_jobs { @_ > 1 ? $_[0]{carbon_server__socket_jobs} = $_[1] : $_[0]{carbon_server__socket_jobs} }
sub thread_pool { @_ > 1 ? $_[0]{carbon_server__thread_pool} = $_[1] : $_[0]{carbon_server__thread_pool} }
=item onerror
the function called when a server attempts to die
Carp::croak by default
=cut
sub onerror { @_ > 1 ? $_[0]{carbon_onerror} = $_[1] : $_[0]{carbon_onerror} }

=item router
the current router used to route http requests
=cut
sub router { @_ > 1 ? $_[0]{carbon_server__router} = $_[1] : $_[0]{carbon_server__router} }


=item start_server()

public method for triggering the server loop to run
NOTE: anything not initialized in the server object before this method is not going to be shared to worker threads

=cut
sub start_server {
	my ($self) = @_;

	$self->start_thread_pool;
	$self->start_server_socket;

	$self->warn(1, "started carbon server on port ". $self->port);
	$self->server_running(1);
	$self->listen_accept_server_loop;

	$self->cleanup;
}

sub start_thread_pool {
	my ($self) = @_;

	$self->thread_pool(Thread::Pool->new({
		workers => 10,
		pre => sub { $self->init_thread(@_) },
		do => sub { return $self->start_thread(@_) },
	}));
}


# called when a worker starts
# mainly necessary for intializing the router
sub init_thread {
	my ($self) = @_;
	$self->router->init_thread if defined $self->router;
}



# creates and sets the server socket
# upgrades should override this method to utilize different types of sockets
sub start_server_socket {
	my ($self) = @_;

	# the primary server socket which will be receiving connections
	my $sock = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->port,
		Listen => SOMAXCONN,
		Reuse => 1,
		Blocking => 0,
	) or $self->die("failed to start socket: $!");
	$self->server_socket ($sock);

	# the socket selector which will store sockets while they are transferring their request
	my $selector = IO::Select->new;
	$self->socket_selector($selector);
}


# the primary io loop of the server which accepts new connections, buffers new requests, dispatches response jobs, and recycling sockets from completed jobs
# probably the most complex part of the server, commented to be as verbose as possible
sub listen_accept_server_loop {
	my ($self) = @_;

	# while the server is running
	while ($self->server_running) {
		# update the thread_pool to receive any completed jobs
		$self->update_thread_pool;
		# update the server socket to receive any new connections
		$self->accept_new_connections;
		# update sockets to receive any new messages and dispatch any jobs necessary
		# this method needs to perform some delay operation to prevent 100% cpu usage
		$self->update_sockets;
	}
}


sub update_thread_pool {
	my ($self) = @_;

	# check any thread pool jobs that have completed
	foreach my $jobid ($self->thread_pool->results) {
		# reclaim any socket whose job has completed
		# say "job [$jobid] completed!"; # JOBS DEBUG
		my $sock = delete $self->socket_jobs->{$jobid};
		$sock = $self->socket_data->{$sock}{socket};
		if ($self->thread_pool->result($jobid)) {
			# re-add it to the selector if the job completed with true status
			$self->socket_selector->add($sock);
		} else {
			# if job returned with false status, we must close the socket and delete record of it
			$self->delete_socket($sock);
		}
	}
}

sub accept_new_connections {
	my ($self) = @_;

	# get any newly accepted sockets
	while (my $sock = $self->server_socket->accept) {
		$sock->blocking(0); # set it to non-blocking
		$self->socket_selector->add($sock); # add it to the selector

		$self->socket_data->{"$sock"} = { socket => $sock, buffer => '', request => undef };
		say "new connection: $sock"; # FH DEBUG
	}
}

sub update_sockets {
	my ($self) = @_;

	# IO::Select doesn't block unless it has at least 1 socket to check on
	# so we need to sleep in that case to prevent 100% cpu usage
	usleep (10 * 1000) unless $self->socket_selector->count;

	# the selector will give us a list of sockets that are ready to read
	foreach my $fh ($self->socket_selector->can_read(10 / 1000)) {
		my $socket_data = $self->socket_data->{"$fh"};
		# read until there is nothing left to read
		my $read = 1;
		my $total = 0;
		while (defined $read and $read > 0) {
			$read = $fh->read($socket_data->{buffer}, 4096 * 16, length $socket_data->{buffer});
			$total += $read if defined $read;
			# say "debug read loop: $read";
		}
		$self->delete_socket($fh) if $total == 0;

		# if there is no request for this socket yet
		unless (defined $socket_data->{request}) {
			# otherwise check if it's ready for header processing
			if ($socket_data->{buffer} =~ /\r?\n\r?\n/) {
				say "serving request: $fh"; # FH DEBUG
				my ($header, $body) = split /\r?\n\r?\n/, $socket_data->{buffer}, 2;
				my $req = $self->parse_http_header($header);

				if (not defined $req) {
					# if the request processing failed, it means that it was an invalid request
					$self->delete_socket($fh);
				} else {
					$socket_data->{request} = $req;
					$socket_data->{buffer} = $body;
				}
			}
		}

		# if it has completed the header transfer
		if (defined $socket_data->{request}) {
			my $req = $socket_data->{request};

			if (defined $req->header('content-length')) { # if it has a content-length
				# check if the whole body has arrived yet
				if ($socket_data->{request}->header('content-length') <= length $socket_data->{buffer}) {
					# set the request content
					$req->content(substr $socket_data->{buffer}, 0, $socket_data->{request}->header('content-length'));
					$socket_data->{buffer} = substr $socket_data->{buffer}, $socket_data->{request}->header('content-length');

					# start the job
					$self->schedule_job($fh, $req);
				}
			} else {
				# if there is no body, start the job immediately
				$self->schedule_job($fh, $req);
			}
		}
	}
}




# transforms a raw http header string into a Request object as well as parsing the uri
# i would prefer to do this in the child threads, but this really is required for grabbing the content-length header
# perhaps i could pass the raw header to a job which will then parse it, realize it has a content-length, and then send it back to the io loop for collecting
# or perhaps there could be a second thread pool just for parsing headers??? nah, that sounds expensive
sub parse_http_header {
	my ($self, $data) = @_;
	my $req = Carbon::Request->parse($data);

	if (defined $req) {
		$req->uri(Carbon::URI->parse($req->uri));
	}

	return $req
}


# schedules a job for completion by a thread_pool worker
# also clears the socket's request storage and removes it from the io-selector
# if it detects that too many jobs are waiting, it will increase the worker count in the thread_pool (up to 64)
sub schedule_job {
	my ($self, $sock, $req) = @_;

	my $jobid = $self->thread_pool->job(fileno $sock, $req);

	$self->socket_selector->remove($sock); # remove it from the selector to not read from the socket for now
	$self->socket_data->{"$sock"}{request} = undef; # no more request to be buffered
	$self->socket_jobs->{$jobid} = "$sock"; # record the jobid for when the job is completed

	my $todo = $self->thread_pool->todo;
	$todo = "$todo"; # i have no idea why, but the value was acting wierd without it

	if ($todo > 2 * $self->thread_pool->workers and $self->thread_pool->workers < 64) {
		$self->thread_pool->workers(2 * $self->thread_pool->workers);
		$self->warn(1, "increased worker count to ". $self->thread_pool->workers);
	}

	# say "job [$jobid] created!"; # JOBS DEBUG

	return $jobid
}


sub delete_socket {
	my ($self, $sock) = @_;

	$self->socket_selector->remove($sock) if $self->socket_selector->exists($sock); # remove it from the selector
	delete $self->socket_data->{"$sock"}; #delete all of its data
	# delete $socket_data{"$sock"}; # delete its cache
	$sock->close; # close it
	say "socket disconnected: $sock"; # FH DEBUG
}


# an automatic clean up function
# this should not be called directly
sub cleanup {
	my ($self) = @_;

	$self->warn(1, "cleaning up server resources");

	$self->server_socket->close;
	$self->server_socket(undef);

	for my $socket_data (values %{$self->socket_data}) {
		$self->delete_socket($socket_data->{socket});
	}
	$self->socket_data(undef);
	$self->socket_jobs(undef);

	$self->thread_pool->abort;
}


=item shutdown ()

sets the server to non-running mode
this will cause the io-loop to exit and enter cleanup() which will collect and close all resources
if a thread_pool job is hanging, then the cleanup method may wait indefinitely for it to finish

=cut
sub shutdown {
	my ($self) = @_;

	if ($self->server_running) {
		$self->warn(1, "shutdown requested");
		$self->server_running(0);
	} else {
		$self->die("shutdown called twice");
	}
}




# this is where the thread starts it job
# receives a socket file descriptor and the associated request with which it must complete and send the response
# returning from this method returns control of the socket back to the server io loop
# returns 1 if the socket should be closed after this request or 0 if it should be kept alive
sub start_thread {
	my ($self, $sock_num, $req) = @_;

	my $sock = $self->restore_socket($sock_num);
	return $self->serve_http_request($sock, $req);
}

# restores the socket from the file descriptor
# extensions such as SSL should override this method
sub restore_socket {
	my ($self, $sock_num) = @_;

	# reopen the socket using fdopen
	my $sock = IO::Socket::INET->new;
	$sock->fdopen($sock_num, 'r+'); # 'rw' stalls

	return $sock
}

=item serve_http_request()

processes the request and sends the response into the socket
in this instance, Carbon dispatches the router to execute the request
extensions which wish to do something special with the socket would need to
override this method to utilize its full potential

=cut
sub serve_http_request {
	my ($self, $sock, $req) = @_;

	my $res;
	eval {
		$res = $self->router->execute($req);
	};
	if ($@) {
		carp "router died: $@";
		$res = Carbon::Response->new('500');
		$res->content("router died: $@");
	}

	unless (defined $res) {
		$res = Carbon::Response->new('400');
		$res->content('Bad Request');
		$res->header('content-type' => 'text/plain');
	}

	$sock->print($res->as_string);

	return not $res->is_error
}





'Carbon is the 15th most abundant element in the Earth\'s crust, and the fourth
most abundant element in the universe by mass after hydrogen, helium, and
oxygen. It is present in all forms of carbon-based life, and in the human body
carbon is the second most abundant element by mass (about 18.5%) after oxygen.
This abundance, together with the unique diversity of organic compounds and
their unusual polymer-forming ability at the temperatures commonly encountered
on Earth, make this element the chemical basis of all known life.

-- Wikipedia'
