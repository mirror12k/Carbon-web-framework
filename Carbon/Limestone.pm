#!/usr/bin/env perl
package Carbon::Limestone;
use parent 'Carbon';
use strict;
use warnings;

use feature 'say';
use JSON;

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


our $CARBON_LIMESTONE_DEBUG_VALUE = 1 + $Carbon::CARBON_DEBUG_VALUE;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

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



use Data::Dumper;

sub serve_http_request {
	my ($self, $sock, $req) = @_;

	if ($req->method('GET') and
			$req->uri->path eq '/' and
			'upgrade' eq lc $req->header('connection') and
			'limestone-database-connection' eq lc $req->header('upgrade') and
			defined $req->content and $req->content ne '') {

		eval {
			return $self->start_limestone_connection($sock, $req);
		};
		if ($@) {
			$self->warn($CARBON_LIMESTONE_DEBUG_VALUE, "limestone connection died: $@");
			return 0
		}

	} else {
		my $res = Carbon::Response->new('400');
		$res->content('Bad Request');
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'text/plain');

		$sock->send($res->as_string);
		return 0
	}
}


sub start_limestone_connection {
	my ($self, $sock, $req) = @_;

	$self->warn($CARBON_LIMESTONE_DEBUG_VALUE, "established limestone database connection: $sock");

	my $data = decode_json $req->content;

	my $connection = Carbon::Limestone::Connection->new;
	$connection->version(1);
	$connection->packet_length_bytes(2);
	$connection->payload_format('FreezeThaw');
	$connection->username('guest');
	$sock->blocking(1);
	$connection->socket($sock);

	my $res = Carbon::Response->new('101');
	$res->header(connection => 'upgrade');
	$res->header(upgrade => 'limestone-database-connection');
	$res->content(encode_json $connection->serialize_settings);
	$res->header('content-length' => length $res->content);
	$res->header('content-type' => 'application/json');

	$sock->send($res->as_string);

	$self->limestone_query_loop($connection);

	$sock->blocking(0);

	$self->warn($CARBON_LIMESTONE_DEBUG_VALUE, "limestone connection disconnected: $sock");

	return 0
}

sub limestone_query_loop {
	my ($self, $con) = @_;

	while (my $query = $con->read_query) {
		# say "i got a query: ", Dumper $query;
		my $res = $self->database->process_query($query);
		$con->write_result($res // Carbon::Limestone::Response->new( type => 'error', error => 'no result' ));
	}

}


sub open_database {
	my ($self, $filepath) = @_;

	$self->database(Carbon::Limestone::Database->new(filepath => $filepath, debug => 1));
}



sub main {
	my $srv = Carbon::Limestone->new( debug => 1, port => 2049, database_filepath => 'test.limedb' );
	$srv->start_server;
}


caller or main(@ARGV)
