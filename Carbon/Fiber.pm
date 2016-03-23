package Carbon::Fiber;

use strict;
use warnings;

use feature 'say';

use List::Util 'any';
use File::Slurp;

use Carbon::Response;



our $CARBON_FIBER_DEBUG_VALUE = 1;


sub new ($%) {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->debug($args{debug} // 0);
	$self->routes([]);

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
sub routes { @_ > 1 ? $_[0]{carbon_fiber__routes} = $_[1] : $_[0]{carbon_fiber__routes} }




sub execute {
	my ($self, $req) = @_;

	# get a response from routes
	my $res = $self->route_request($req);

	# if no response was generated, we need to write one ourselves
	unless (defined $res) {
		$res = Carbon::Response->new('400');
		$res->content('Bad Request');
	}

	# some default values
	$res->protocol($res->protocol // $req->protocol);
	if (defined $res->content) {
		$res->header('content-type', $res->header('content-type') // 'text/plain');
		$res->header('content-length', $res->header('content-length') // length $res->content);
	}
	unless (defined $res->header('connection')) {
		if ($res->is_error) {
			$res->header('connection' => 'close');
		} else {
			$res->header('connection' => 'keep-alive');
		}
	}

	return $res
}


sub route_request {
	my ($self, $req) = @_;
	my $res;
	for my $route (@{$self->routes}) {
		if ($req->uri->path =~ $route->{regex}
			and (not defined $route->{options}{methods} or any { $req->method eq $_ } @{$route->{options}{methods}})) {
			$res = $_->($self, $req, $res) for @{$route->{functions}};
		}
	}
	return $res;
}

sub init_thread {
	my ($self) = @_;
	# do nothing
	# required otherwise the worker crashes on the pre subroutine
}


sub route {
	my ($self, $path, $method, $opts) = @_;
	$opts //= {};
	# accepted options:
	# method => [<strings of allowed methods>]

	$method = ref $method eq 'ARRAY' ? [@$method] : [$method];
	$path = quotemeta $path unless ref $path eq 'Regexp';
	$path = qr/\A$path\Z/;

	my $route = { regex => $path, functions => $method, options => $opts };
	push @{$self->routes}, $route;

	$self->warn($CARBON_FIBER_DEBUG_VALUE, "added route for path $path");

	return $route
}


sub route_directory {
	my ($self, $path, $directory, $opts) = @_;

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req, $res) = @_;

		# some basic munging and filtering of the path
		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\A\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		if (-e $loc) { # if the location exists
			if (-f _) { # if it's a file
				$res //= Carbon::Response->new;
				$res->code('200');
				my $data = read_file($loc, binmode => ':raw');
				$res->content($data);
				$res->header('content-type' => 'text/plain');
			} elsif (-d _) { # if it's a directory
				$res //= Carbon::Response->new;
				$res->code('403');
				$res->content('Forbidden');
				$res->header('content-type' => 'text/plain');
			}
		} else { # if the location doesn't exist
			$res //= Carbon::Response->new;
			$res->code('404');
			$res->content("Not Found: $loc");
		}

		return $res
	}, $opts);
}

sub route_map {
	my ($self, $path, $map, $opts) = @_;

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req, $res) = @_;
		my $new_path = $req->uri->path;
		# say "debug matched: ", $new_path;
		return $res unless $new_path =~ s/\A$path/$map/; # replace or fail out
		# say "debug transformed: ", $new_path;

		my $route_args = join '&', map "$_=$+{$_}", keys %+;
		if (defined $req->uri->query and $req->uri->query ne '') {
			$req->uri->query($req->uri->query . '&' . $route_args);
		} else {
			$req->uri->query($route_args);
		}
		$req->uri->path($new_path);
		return $res
	}, $opts);
}


sub simplify_filepath {
	my ($self, $filepath) = @_;
	if ('/' eq substr $filepath, 0, 1) {
		return '/' . join '/', grep {$_ ne '' and $_ ne '.'} split '/', $filepath
	} else {
		return join '/', grep {$_ ne '' and $_ ne '.'} split '/', $filepath
	}
}


'To produce a carbon fiber, the carbon atoms are bonded together in crystals
that are more or less aligned parallel to the long axis of the fiber as the
crystal alignment gives the fiber high strength-to-volume ratio (making it
strong for its size). Several thousand carbon fibers are bundled together to
form a tow, which may be used by itself or woven into a fabric.

The properties of carbon fibers, such as high stiffness, high tensile strength,
low weight, high chemical resistance, high temperature tolerance and low thermal
expansion, make them very popular in aerospace, civil engineering, military,
and motorsports, along with other competition sports.

--  Wikipedia'

