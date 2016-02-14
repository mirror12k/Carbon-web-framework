package Carbon;

use strict;
use warnings;

use feature 'say';


use Carp;
use IO::Socket::INET;
use IO::Select;
use Thread::Pool;
use threads::shared;
use Time::HiRes 'usleep';

# use HTTP::Request;
# use HTTP::Response;

use Carbon::URI;
use Carbon::Request;
use Carbon::Response;



# TODO:
# caching routes
# route shortcutting
# route excluding

# graphite plugin for anthracite
	# graphite runtime variable
	# graphite template compilation
# sql database plugin for anthracite
# CGI runtime
# FastCGI runtime?


# awesome names to use:

# methane, oil, coal
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
# carbon fibre-reinforced carbon ( aka carbon-carbon )

# diamond

# limestone -> document database engine
# fossiliferous limestone
# coral
#chalk

# dolomite
# calcite
# azurite
# malachite




our $CARBON_DEBUG_VALUE = 1;


sub new ($%) {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->debug($args{debug} // 0);

	$self->port($args{port} // 2048);
	$self->onerror($args{onerror} // \&Carp::croak);

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
	$self->onerror->($self, @_);
	CORE::die "returning from onerror is not allowed";
}


sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }

sub server_running { @_ > 1 ? $_[0]{carbon_server__running} = $_[1] : $_[0]{carbon_server__running} }

sub port { @_ > 1 ? $_[0]{carbon_server__port} = $_[1] : $_[0]{carbon_server__port} }
sub server_socket { @_ > 1 ? $_[0]{carbon_server__server_socket} = $_[1] : $_[0]{carbon_server__server_socket} }
sub socket_selector { @_ > 1 ? $_[0]{carbon_server__socket_selector} = $_[1] : $_[0]{carbon_server__socket_selector} }
sub socket_data { @_ > 1 ? $_[0]{carbon_server__socket_data} = $_[1] : $_[0]{carbon_server__socket_data} }
sub socket_jobs { @_ > 1 ? $_[0]{carbon_server__socket_jobs} = $_[1] : $_[0]{carbon_server__socket_jobs} }
sub thread_pool { @_ > 1 ? $_[0]{carbon_server__thread_pool} = $_[1] : $_[0]{carbon_server__thread_pool} }
sub onerror { @_ > 1 ? $_[0]{carbon_onerror} = $_[1] : $_[0]{carbon_onerror} }

sub router { @_ > 1 ? $_[0]{carbon_server__router} = $_[1] : $_[0]{carbon_server__router} }


# public method for triggering the server loop to run
# NOTE: anything not initialized in the server object before this method is not going to be shared to worker threads
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

	# my $server_socket = $self->socket;
	# my $selector = IO::Select->new;
	# my %socket_data; # data buffer for each socket until the head or body arrives completely
	# my %socket_request; # request storage for each socket for when the head has arrived, but the body is still transferring
	# my %socket_jobs; # socket storage for each running job to prevent the socket from being garbage collected

	# while the server is running
	while ($self->server_running) {

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
		
		# get any newly accepted sockets
		while (my $sock = $self->server_socket->accept) {
			# say "debug accepting";
			$sock->blocking(0); # set it to no blocking
			$self->socket_selector->add($sock); # add it to the selector
			# $socket_data{"$sock"} = ''; # create an empty cache for it

			$self->socket_data->{"$sock"} = { socket => $sock, buffer => '', request => undef };
			# say "new connection: $sock"; # FH DEBUG
		}

		# IO::Select doesn't block unless it has at least 1 socket to check on
		# so we need to sleep in that case to prevent 100% cpu usage
		usleep (10 * 1000) unless $self->socket_selector->count;

		# say "active socket jobs: ", scalar keys %socket_jobs; # JOBS DEBUG

		# the selector will give us a list of sockets that are ready to read
		foreach my $fh ($self->socket_selector->can_read(10 / 1000)) {
			# say "debug peaking";
			$fh->recv(my $data, 1, MSG_PEEK | MSG_DONTWAIT);
			if ($data eq '') { # if it's a disconnected socket
				$self->delete_socket($fh);
			} else { # else if it's a message
				my $socket_data = $self->socket_data->{"$fh"};
				# read until there is nothing left to read
				my $read = 1;
				while (defined $read and $read > 0) {
					# say "debug read loop: $read";
					# 4096 * 16
					$read = $fh->read($socket_data->{buffer}, 10, length $socket_data->{buffer});
				} 

				unless (defined $socket_data->{request}) { # otherwise check if it's ready for header processing
					if ($socket_data->{buffer} =~ /\r?\n\r?\n/) {
						# say "serving request: $fh"; # FH DEBUG
						my ($header, $body) = split /\r?\n\r?\n/, $socket_data->{buffer}, 2;
						my $req = $self->parse_http_header($header);

						# if the request processing failed, it means that it was an invalid request
						if (not defined $req) {
							$self->delete_socket($fh);
						} else {
							$socket_data->{request} = $req;
							$socket_data->{buffer} = $body;
						}
					}
				}

				if (defined $socket_data->{request}) { # if it already has completed the header transfer
					# say "got some body data: '", $socket_data->{buffer}, "'";
					my $req = $socket_data->{request};
					if (defined $req->header('content-length')) {
						if ($socket_data->{request}->header('content-length') <= length $socket_data->{buffer}) {
							# set the request content
							$req->content(substr $socket_data->{buffer}, 0, $socket_data->{request}->header('content-length'));
							$socket_data->{buffer} = substr $socket_data->{buffer}, $socket_data->{request}->header('content-length');

							# start the job
							$self->schedule_job($fh, $req); #$self->thread_pool->job(fileno $fh, $req);
						}
					} else {
						$self->schedule_job($fh, $req); #$self->thread_pool->job(fileno $fh, $req);
					}
				}
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


sub schedule_job {
	my ($self, $sock, $req) = @_;

	my $jobid = $self->thread_pool->job(fileno $sock, $req);

	$self->socket_selector->remove($sock); # remove it from the selector to not read from the socket for now
	$self->socket_data->{"$sock"}{request} = undef; # no more request to be buffered
	$self->socket_jobs->{$jobid} = "$sock"; # record the jobid for when the job is completed

	my $todo = $self->thread_pool->todo;
	$todo = "$todo";
	# $self->warn(1, "jobs todo: ". $todo) if 0 < $todo;
	if ($todo > 2 * $self->thread_pool->workers and $self->thread_pool->workers < 100) {
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
	# say "socket disconnected: $sock"; # FH DEBUG
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



sub shutdown {
	my ($self) = @_;

	$self->warn(1, "shutdown requested");
	$self->server_running(0);
}




# this is where the thread starts it job
# receives a socket file descriptor and the associated request with which it must complete and send the response
# returning from this method returns control of the socket back to the server io loop
# returns 1 if the socket should be closed after this request or 0 if it should be kept alive
sub start_thread {
	my ($self, $sock_num, $req) = @_;
	my $sock = $self->restore_socket($sock_num);

	return $self->serve_http_request($sock, $req)
}

# restores the socket from the file descriptor
# extensions such as SSL should override this method
sub restore_socket {
	my ($self, $sock_num) = @_;

	# reopen the socket using fdopen
	my $sock = IO::Socket::INET->new;
	$sock->fdopen($sock_num, 'r'); # even though only 'r' permissions may look wrong, it seems to work just fine, where as 'rw' stalls

	return $sock
}

# processes the request and sends the response into the socket
# in this instance, Carbon dispatches the router to execute the request
# extensions which wish to do something special with the socket would need to
# override this method to utilize its full potential
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

	$sock->send($res->as_string);

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
