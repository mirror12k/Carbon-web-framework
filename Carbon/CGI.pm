package Carbon::CGI;
use parent 'Carbon::Fiber';
use strict;
use warnings;

use feature 'say';


sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	$self->command_line($args{command_line} // 'php5-cgi');

	return $self
}

sub command_line { @_ > 1 ? $_[0]{carbon_cgi__command_line} = $_[1] : $_[0]{carbon_cgi__command_line} }




sub route_cgi {
	my ($self, $path, $directory, $opts) = @_;

	my $suffix = $opts->{suffix} // ''; # allows a file suffix to be appended

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req, $res) = @_;

		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\A\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		# say "debug loc: $loc";

		if (-e -f "$loc$suffix") { # if the file exists
			$res = $self->execute_cgi("$loc$suffix", $req);
		# } elsif (-d $loc and -e -f "$loc/index$suffix") { # if it's a directory, but we have an index file
		# 	$res = $self->execute_dynamic_file("$loc/index$suffix", $req, $res);

		} else { # otherwise it's not found
			$res //= Carbon::Response->new;
			$res->code('404');
			$res->content("Not Found");
			$res->header('content-type' => 'text/plain');
		}

		return $res
	}, $opts);
}

sub execute_cgi {
	my ($self, $filepath, $req) = @_;

	my $cmd = $self->command_line;

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		PATH_INFO => $req->uri->path,
		PATH_TRANSLATED => $req->uri->path, # pretend it's the same thing
		QUERY_STRING => $req->uri->query,
		REMOTE_ADDR => '127.0.0.1',
		# REMOTE_HOST =>
		REQUEST_METHOD => $req->method,
		SCRIPT_NAME => $filepath,
		# php cgi doesn't seem to care for SCRIPT_NAME, instead it wants SCRIPT_FILENAME
		SCRIPT_FILENAME => $filepath,
		SERVER_NAME => '127.0.0.1',
		SERVER_PORT => '22222',
		SERVER_PROTOCOL => $req->protocol,
		SERVER_SOFTWARE => 'Carbon::CGI/0.01',
		REDIRECT_STATUS => '',
	);
	for my $key (keys %{$req->headers}) {
		$ENV{'HTTP_' . uc ($key =~ s/-/_/gr)} = join ', ', $req->header($key);
	}
	# while (my ($k, $v) = each %ENV) {
	# 	say "env: $k => $v";
	# }
	my $envcmd  = 'env -i ' . join ' ', map "'$_=$ENV{$_}'", keys %ENV;
	# my $output = system "$cmd";
	my $output = `$envcmd $cmd`;
	# say "got output: [$output]";
	if ($output =~ /\AStatus:\s*/) {
		$output =~ s/\AStatus:\s*/HTTP\/1.1 /;
	} elsif ($output =~ /\ALocation:\s*/) {
		$output = "HTTP/1.1 303 See Other\r\n$output";
	} else {
		$output = "HTTP/1.1 200 OK\r\n$output";
	}
	# say "made: [$output]";
	return Carbon::Response->parse($output);
}




1;
