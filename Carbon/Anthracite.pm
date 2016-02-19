package Carbon::Anthracite;
use strict;
use warnings;

use feature 'say';

use File::Slurp;


use Carbon::Anthracite::HTMLParser;
use Carbon::Anthracite::CompiledFile;
use Carbon::Anthracite::Runtime;

sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->debug($args{debug} // 0);
	$self->plugins($args{plugins} // []);
	$self->{carbon_anthracite__echo_accumulator} = '';

	for my $plugin (@{$self->plugins}) {
		$plugin->initialize($self);
	}

	return $self
}

sub warn {
	my ($self, $level, $message) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		CORE::warn "[". (caller)[0] ."]: $message\n";
	}
}



sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub parser { @_ > 1 ? $_[0]{carbon_anthracite__parser} = $_[1] : $_[0]{carbon_anthracite__parser} }
sub plugins { @_ > 1 ? $_[0]{carbon_anthracite__plugins} = $_[1] : $_[0]{carbon_anthracite__plugins} }


sub add_plugin {
	my ($self, $plugin) = @_;
	push @{$self->plugins}, $plugin;
	$plugin->initialize($self);
}


sub init_thread {
	my ($self) = @_;

	for my $plugin (@{$self->plugins}) {
		$plugin->init_thread;
	}
}


sub compile {
	my ($self, $router, $file) = @_;

	$self->warn(1, "compiling '$file'");

	my $data = Carbon::Anthracite::CompiledFile->new;
	$data->filepath($file);
	$data->router($router);

	my $text = read_file($file);
	$self->parser(Carbon::Anthracite::HTMLParser->new($text));

	my $code = $self->code_header($data);
	for my $plugin (@{$self->plugins}) {
		$code .= $plugin->code_header($data);
	}

	# say "code header: $code";
	TOKEN: while (my @token = $self->parser->get_token) {
		# say "debug got token: [ @token ]";
		# first let the plugins view the token
		for my $plugin (@{$self->plugins}) {
			my ($new_code, $new_token) = $plugin->compile_token([@token]);
			if ($new_code ne '') {
				$code .= $self->get_echo_code;
				$code .= $new_code; # append any code
			}
			next TOKEN unless defined $new_token; # if it didn't return a token, we should stop propagating it
			@token = @$new_token;
		}
		$code .= $self->compile_token(@token);
	}

	for my $plugin (@{$self->plugins}) {
		$code .= $plugin->code_tail($data);
	}
	$code .= $self->code_tail($data);

	# say "compiled code: $code";

	my $compiled = eval $code;
	if ($@) {
		CORE::die "compilation failed: $@";
	} else {
		$data->code($compiled);
	}

	return $data
}




sub compile_token {
	my ($self, $token_type, $raw, $tag_type, $tag_data) = @_;

	if ($token_type eq 'tag' or $token_type eq 'text') {
		$self->{carbon_anthracite__echo_accumulator} .= $raw;
		return '';
	} elsif ($token_type eq 'directive') {
		if ($tag_type eq 'perl') {
			my $code = '';
			$code .= $self->get_echo_code;
			$code .= $tag_data;
		} else {
			die "unknown directive type: $tag_type";
		}
	} else {
		die "unknown token type: $token_type";
	}
}

sub code_header {
	my ($self, $data) = @_;
	return 'sub {
# this is necessary to prevent redefinition of symbols			
package Carbon::Anthracite::Dynamic::'. ($data->filepath =~ s/[^a-zA-Z_]/_/gr) .';
our ($runtime) = @_;

use subs qw/ echo /;
local *echo = sub { $runtime->echo(@_) };
'
}

sub code_tail {
	my ($self) = @_;
	my $code = '';
	$code .= $self->get_echo_code;
	$code .= "}\n";
	return $code
}


sub get_echo_code {
	my ($self) = @_;
	my $code;
	if ($self->{carbon_anthracite__echo_accumulator} ne '') {
		$code = $self->code_wrap_text($self->{carbon_anthracite__echo_accumulator});
		$self->{carbon_anthracite__echo_accumulator} = '';
	}
	return $code
}

sub code_wrap_text {
	my ($self, $text) = @_;
	$text =~ s/\\/\\\\/g;
	$text =~ s/'/\\'/g;
	return ";echo('$text');\n"
}


sub create_runtime {
	my ($self, $compiled, $request) = @_;

	my $runtime = Carbon::Anthracite::Runtime->new($request);
	$runtime->router($compiled->router);

	for my $plugin (@{$self->plugins}) {
		$runtime = $plugin->create_runtime($compiled, $runtime);
	}
	
	return $runtime
}





'Anthracite is the most metamorphosed type of coal (but still represents
low-grade metamorphism), in which the carbon content is between 92.1% and 98%.
The term is applied to those varieties of coal which do not give off tarry or
other hydrocarbon vapours when heated below their point of ignition.
...
The principal use of anthracite today is for a domestic fuel in either hand-fired
stoves or automatic stoker furnaces. It delivers high energy per its weight and
burns cleanly with little soot, making it ideal for this purpose.

-- Wikipedia'
