package Carbon::Nanotube;
use parent 'Carbon::Fiber';
use strict;
use warnings;

use feature 'say';

use File::Slurp;

use Carbon::Response;
use Carbon::Anthracite;


our $CARBON_NANOTUBE_DEBUG_VALUE = 1 + $Carbon::Fiber::CARBON_FIBER_DEBUG_VALUE;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	$self->compiler($args{compiler} // Carbon::Anthracite->new);
	$self->compiled_cache({});
	$self->pre_includes([]);

	return $self
}

sub compiler { @_ > 1 ? $_[0]{carbon_nanotube__compiler} = $_[1] : $_[0]{carbon_nanotube__compiler} }
sub compiled_cache { @_ > 1 ? $_[0]{carbon_nanotube__compiled_cache} = $_[1] : $_[0]{carbon_nanotube__compiled_cache} }
sub pre_includes { @_ > 1 ? $_[0]{carbon_nanotube__pre_includes} = $_[1] : $_[0]{carbon_nanotube__pre_includes} }




# called when a worker thread is started
sub init_thread {
	my ($self) = @_;
	
	$self->SUPER::init_thread;
	$self->compiler->init_thread;

	$self->execute_pre_includes;
}



# adds a file or directory route to the routing table
# any files pointed to by the routes will be compiled and executed by the loaded compiler
sub route_dynamic {
	my ($self, $path, $directory, $opts) = @_;

	my $suffix = $opts->{suffix} // '.am'; # allows a file suffix to be appended

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req, $res) = @_;

		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\A\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		# say "debug loc: $loc";

		if (-e -f "$loc$suffix") { # if the file exists
			$res = $self->execute_dynamic_file("$loc$suffix", $req, $res);
		} elsif (-d $loc and -e -f "$loc/index$suffix") { # if it's a directory, but we have an index file
			$res = $self->execute_dynamic_file("$loc/index$suffix", $req, $res);

		} else { # otherwise it's not found
			$res //= Carbon::Response->new;
			$res->code('404');
			$res->content("Not Found");
			$res->header('content-type' => 'text/plain');
		}

		return $res
	}, $opts);
}

# given a filepath or directory, it will compile each file to cache it for future use
sub pre_compile_dynamic {
	my ($self, $filepath) = @_;
	unless (-e $filepath) {
		$self->die ("attempt to pre-compile invalid path: '$filepath'");
	} else {
		if (-f $filepath) {
			# compiling the dynamic file will push it into the cache
			$self->compile_dynamic_file($filepath);
		} elsif (-d $filepath) {
			for my $file (read_dir($filepath)) {
				$self->pre_compile_dynamic("$filepath/$file");
			}
		}
	}
}

# given a filepath or directory, it will collect all those files as pre-include
# pre-include files are executed once at the start of a worker thread
# this allows libraries and database connections to be setup once and serve many http requests
sub pre_include_dynamic {
	my ($self, $filepath) = @_;
	unless (-e $filepath) {
		$self->die ("attempt to pre-include invalid path: '$filepath'");
	} else {
		if (-f $filepath) {
			push @{$self->pre_includes}, $filepath;
		} elsif (-d $filepath) {
			for my $file (read_dir($filepath)) {
				$self->pre_include_dynamic("$filepath/$file");
			}
		}
	}
}

# compile and execute all pre-included files
sub execute_pre_includes {
	my ($self) = @_;
	for my $filepath (@{$self->pre_includes}) {
		$self->execute_dynamic_file($filepath);
	}
}

# compile a dynamic file and create a new runtime in which to run it and future files
sub execute_dynamic_file {
	my ($self, $filepath, $req, $res) = @_;

	my $compiled = $self->compile_dynamic_file($filepath);
	my $runtime = $self->compiler->create_runtime($compiled, $req);

	$runtime->execute($compiled);

	$res = $runtime->produce_response;

	return $res
}

# compile and run a dynamic file in the context of an already existing runtime
sub include_dynamic_file {
	my ($self, $runtime, $filepath, $req) = @_;

	my $compiled = $self->compile_dynamic_file($filepath);
	return $runtime->execute($compiled);
}



sub compile_dynamic_file {
	my ($self, $filepath) = @_;
	# simplify it to allow better caching
	$filepath = $self->simplify_filepath($filepath);

	if (exists $self->compiled_cache->{$filepath}) {
		return $self->compiled_cache->{$filepath};
	} else {
		my $compiled = $self->compiler->compile($self, $filepath);
		$self->compiled_cache->{$filepath} = $compiled;
		return $compiled
	}
}




'Nanotubes are members of the fullerene structural family. Their name is derived
from their long, hollow structure with the walls formed by one-atom-thick sheets
of carbon, called graphene. These sheets are rolled at specific and discrete
("chiral") angles, and the combination of the rolling angle and radius decides
the nanotube properties
...
The strength and flexibility of carbon nanotubes makes them of potential use in
controlling other nanoscale structures, which suggests they will have an
important role in nanotechnology engineering.

-- Wikipedia'

