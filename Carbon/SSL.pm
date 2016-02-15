package Carbon::SSL;
use parent 'Carbon';
use strict;
use warnings;

use feature 'say';

use IO::Socket::INET;
use IO::Socket::SSL;
use Carp;







# I give up, i can't seem to transfer a working IO::Socket::SSL between threads
# instead i've done a work around where the socket isn't transferred, instead the response object is
# transfered back to the IO thread to be sent to the socket

# this gives me an idea:
# a single thread accept()ing connections
# a thread pool for reading and printing data to/from sockets
# another thread pool for processing requests



sub new ($%) {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	$self->ssl_certificate($args{ssl_certificate}) if defined $args{ssl_certificate};
	$self->ssl_key($args{ssl_key}) if defined $args{ssl_key};

	return $self
}



sub ssl_certificate { @_ > 1 ? $_[0]{carbon_ssl__ssl_certificate} = $_[1] : $_[0]{carbon_ssl__ssl_certificate} }
sub ssl_key { @_ > 1 ? $_[0]{carbon_ssl__ssl_key} = $_[1] : $_[0]{carbon_ssl__ssl_key} }


sub start_server_socket {
	my ($self) = @_;

	# the primary server socket which will be receiving connections
	my $sock = IO::Socket::SSL->new(
		Proto => 'tcp',
		LocalPort => $self->port,
		Listen => SOMAXCONN,
		Reuse => 1,
		Blocking => 0,

		SSL_server => 1,
		SSL_cert_file => $self->ssl_certificate // $self->die ('ssl certificate required'),
		SSL_key_file => $self->ssl_key // $self->die ('ssl key required'),
	) or $self->die("failed to start socket: $!");
	$self->server_socket ($sock);

	# the socket selector which will store sockets while they are transferring their request
	my $selector = IO::Select->new;
	$self->socket_selector($selector);
}


sub start_thread {
	my ($self, $sock_num, $req) = @_;

	return $self->serve_http_request($req);
}


sub serve_http_request {
	my ($self, $req) = @_;

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

	return $res
}



sub update_thread_pool {
	my ($self) = @_;

	# check any thread pool jobs that have completed
	foreach my $jobid ($self->thread_pool->results) {
		# reclaim any socket whose job has completed
		# say "job [$jobid] completed!"; # JOBS DEBUG
		my $sock = delete $self->socket_jobs->{$jobid};
		$sock = $self->socket_data->{$sock}{socket};
		my $res = $self->thread_pool->result($jobid);
		$sock->print($res->as_string) if defined $res;
		unless ($res->is_error) {
			# re-add it to the selector if the job completed with true status
			$self->socket_selector->add($sock);
		} else {
			# if job returned with false status, we must close the socket and delete record of it
			$self->delete_socket($sock);
		}
	}
}




1;

