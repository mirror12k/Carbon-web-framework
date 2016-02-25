package Carbon::Limestone::Connection;
use strict;
use warnings;

use feature 'say';

use JSON;
use FreezeThaw qw/ freeze thaw /;
use IO::Socket::INET;
use IO::Socket::SSL;
use Time::HiRes 'usleep';

use Carbon::Request;
use Carbon::Response;
use Carbon::Limestone::Query;
use Carbon::Limestone::Result;

sub new {
	my $class = shift;
	my $self = bless {}, $class;

	# some defaults
	$self->version(1);
	$self->packet_length_bytes(2);
	$self->payload_format('FreezeThaw');

	$self->is_closed(0);

	$self->{read_buffer} = '';
	$self->{read_expected_size} = undef;

	return $self
}

sub version { @_ > 1 ? $_[0]{limestone_connection__version} = $_[1] : $_[0]{limestone_connection__version} }
sub packet_length_bytes { @_ > 1 ? $_[0]{limestone_connection__packet_length_bytes} = $_[1] : $_[0]{limestone_connection__packet_length_bytes} }
sub payload_format { @_ > 1 ? $_[0]{limestone_connection__payload_format} = $_[1] : $_[0]{limestone_connection__payload_format} }
sub username { @_ > 1 ? $_[0]{limestone_connection__username} = $_[1] : $_[0]{limestone_connection__username} }

sub socket { @_ > 1 ? $_[0]{limestone_connection__socket} = $_[1] : $_[0]{limestone_connection__socket} }
sub is_closed { @_ > 1 ? $_[0]{limestone_connection__is_closed} = $_[1] : $_[0]{limestone_connection__is_closed} }
sub last_read { @_ > 1 ? $_[0]{limestone_connection__last_read} = $_[1] : $_[0]{limestone_connection__last_read} }

sub set_settings {
	my ($self, $settings) = @_;
	if (defined $settings->{version} and $settings->{version} eq '1') {
		$self->version($settings->{version});
	} else {
		die "invalid version in settings";
	}

	if (defined $settings->{packet_length_bytes} and $settings->{packet_length_bytes} eq '2') {
		$self->packet_length_bytes($settings->{packet_length_bytes});
	} else {
		die "invalid packet_length_bytes in settings";
	}

	if (defined $settings->{payload_format} and $settings->{payload_format} eq 'FreezeThaw') {
		$self->payload_format($settings->{payload_format});
	} else {
		die "invalid payload_format in settings";
	}
}

sub serialize_settings {
	my ($self) = @_;
	return {
		version => $self->version,
		packet_length_bytes => $self->packet_length_bytes,
		payload_format => $self->payload_format,
		username => $self->username,
	}
}




sub connect_client {
	my ($self, $hostport) = @_;
	my $sock = $self->socket(IO::Socket::SSL->new(
		PeerAddr => $hostport,
		SSL_verify_mode => SSL_VERIFY_NONE, # TODO: fix somehow
	) or return "connection failed: $!, $SSL_ERROR");

	my $req = Carbon::Request->new;
	$req->method('GET');
	$req->uri('/');
	$req->header(connection => 'Upgrade');
	$req->header(upgrade => 'limestone-database-connection');
	$req->content(encode_json $self->serialize_settings);
	$req->header('content-length' => length $req->content);
	$req->header('content-type' => 'application/json');

	$sock->print($req->as_string);

	my $data = '';
	while (<$sock>) {
		$data .= $_;
		s/\r?\n//;
		last if $_ eq '';
	}
	# say "res: $data";
	my $res = Carbon::Response->parse($data);

	if ($res->code eq '101' and
			defined $res->header('connection') and 'upgrade' eq lc $res->header('connection') and
			defined $res->header('upgrade') and 'limestone-database-connection' eq lc $res->header('upgrade') and
			defined $res->header('content-type') and 'application/json' eq $res->header('content-type') and
			defined $res->header('content-length') and 0 < int $res->header('content-length')) {

		my $read = $sock->read(my $body, int $res->header('content-length'));
		return 'didnt send settings' unless defined $read and $read == int $res->header('content-length');
		$res->content($body);
		$self->set_settings(decode_json $res->content);

		$sock->blocking(0);

		return
	} else {
		return 'server didnt accept the connection'
	}

}


sub read_to_buffer {
	my ($self) = @_;

	my $read = 1;
	my $total = 0;
	while (defined $read and $read > 0) {
		$read = $self->socket->read($self->{read_buffer}, 4096 * 16, length $self->{read_buffer});
		$total += $read if defined $read;
		# say "debug read loop: $read";
	}

	# say "read $total bytes";
	return $total
}

sub read_packet {
	my ($self) = @_;

	my $read = $self->read_to_buffer;

	unless (defined $self->{read_expected_size}) {
		if ($self->packet_length_bytes <= length $self->{read_buffer}) {
			my $length = substr $self->{read_buffer}, 0, $self->packet_length_bytes;
			$self->{read_buffer} = substr $self->{read_buffer}, $self->packet_length_bytes;

			if ($self->packet_length_bytes == 2) {
				$length = unpack 'n', $length;
			} elsif ($self->packet_length_bytes == 4) {
				$length = unpack 'N', $length;
			} else {
				die "invalid packet_length_bytes setting: " . $self->packet_length_bytes;
			}

			# say "got length: $length";
			$self->{read_expected_size} = $length;
		}
	}

	if (defined $self->{read_expected_size}) {
		if ($self->{read_expected_size} <= length $self->{read_buffer}) {
			my $data = substr $self->{read_buffer}, 0, $self->{read_expected_size};
			$self->{read_buffer} = substr $self->{read_buffer}, $self->{read_expected_size};

			if ($self->payload_format eq 'FreezeThaw') {
				($data) = thaw $data;
			} else {
				die "invalid payload_format setting: " . $self->payload_format;
			}

			$self->{read_expected_size} = undef;
			return $data
		}
	}

	$self->last_read($read);
	# # if we haven't read a single byte nor have we produced a packet, we must be in closed state
	# if ($read == 0) {
	# 	say "read 0, closing socket";
	# 	$self->is_closed(1);
	# }

	return
}

sub write_packet {
	my ($self, $data) = @_;

	if ($self->payload_format eq 'FreezeThaw') {
		$data = freeze $data;
	} else {
		die "invalid payload_format setting: " . $self->payload_format;
	}

	my $length = length $data;

	if ($self->packet_length_bytes == 2) {
		die "attempt to encode value larger than 2^16 with packet_length_bytes of 2" if $length > 65536;
		$length = pack 'n', $length;
	} elsif ($self->packet_length_bytes == 4) {
		die "attempt to encode value larger than 2^32 with packet_length_bytes of 4" if $length > 4294967296;
		$length = pack 'N', $length;
	} else {
		die "invalid packet_length_bytes setting: " . $self->packet_length_bytes;
	}
	$self->socket->print($length . $data);
}


sub read_query {
	my ($self) = @_;

	my $data = $self->read_packet;
	return unless defined $data;

	$data = Carbon::Limestone::Query->new(%$data);

	return $data
}


sub write_query {
	my ($self, $query) = @_;
	$self->write_packet($query->serialize);
}


sub write_result {
	my ($self, $result) = @_;
	$self->write_packet($result->serialize);
}

sub read_result {
	my ($self) = @_;

	my $data = $self->read_packet;
	return unless defined $data;

	$data = Carbon::Limestone::Result->new(%$data);

	return $data
}

sub read_result_blocking {
	my ($self) = @_;

	my $res;
	usleep (1000 * 50) until $res = $self->read_result($res);

	return $res
}

1;
