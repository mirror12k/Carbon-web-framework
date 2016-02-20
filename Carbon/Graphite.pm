package Carbon::Graphite;
use strict;
use warnings;

use feature 'say';


# graphite engine

use Carbon::Graphite::Parser;
use Carbon::Graphite::Helper;
use Carbon::Graphite::Template;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->templates({});
	$self->helpers({
		template => Carbon::Graphite::Helper->new(\&helper_template),
		foreach => Carbon::Graphite::Helper->new(\&helper_foreach),
		if => Carbon::Graphite::Helper->new(\&helper_if),
		elsif => Carbon::Graphite::Helper->new(\&helper_elsif),
		else => Carbon::Graphite::Helper->new(\&helper_else),
		with => Carbon::Graphite::Helper->new(\&helper_with),
		namespace => Carbon::Graphite::Helper->new(\&helper_namespace),
	});

	$self->condition_else(0);
	$self->namespace_stack([]);

	return $self
}



sub templates { @_ > 1 ? $_[0]{carbon_graphite__templates} = $_[1] : $_[0]{carbon_graphite__templates} }
sub helpers { @_ > 1 ? $_[0]{carbon_graphite__helpers} = $_[1] : $_[0]{carbon_graphite__helpers} }
sub condition_else { @_ > 1 ? $_[0]{carbon_graphite__condition_else} = $_[1] : $_[0]{carbon_graphite__condition_else} }
sub namespace_stack { @_ > 1 ? $_[0]{carbon_graphite__namespace_stack} = $_[1] : $_[0]{carbon_graphite__namespace_stack} }


# api functions

sub current_namespace {
	my ($self) = @_;
	if (@{$self->namespace_stack}) {
		return join '::', @{$self->namespace_stack}
	} else {
		return
	}
}

sub push_namespace {
	my ($self, $namespace) = @_;
	push @{$self->namespace_stack}, $namespace;
}
sub pop_namespace {
	my ($self) = @_;
	pop @{$self->namespace_stack};
}

sub template {
	my ($self, $name, $value) = @_;

	my $namespace = $self->current_namespace;
	$name = "${namespace}::$name" if defined $namespace;

	# say "accessing template '$name'";

	if (@_ > 2) {
		return $self->templates->{$name} = $value;
	} else {
		return $self->templates->{$name}
	}
}

sub helper {
	my ($self, $name, $value) = @_;
	if (@_ > 2) {
		return $self->helpers->{$name} = $value;
	} else {
		return $self->helpers->{$name}
	}
}




# graphite compilation methods

sub compile_graphite_directive {
	my ($self, $block) = @_;
	my $code = $self->code_header;

	$code .= $self->compile_graphite($block);

	$code .= $self->code_tail;
	return $code
}

sub compile_graphite {
	my ($self, $text) = @_;

	my $parser = Carbon::Graphite::Parser->new($text);

	my @helper_stack;
	my $code = '';

	while (my ($type, $text, $raw) = $parser->get_token) {
		if ($type eq 'helper') {
			my $block = $parser->get_until_end_helper;
			if (defined $self->helper($text)) {
				$code .= $self->helper($text)->execute($self, $block);
			} else {
				die "attempt to invoke unknown helper '$text'";
			}
		} elsif ($type eq 'end_helper') {
			die "out of order end helper";
		} elsif ($type eq 'text') {
			$code .= $self->compile_text($text);
		} else {
			die "unknown token type '$type'";
		}
	}
	return $code
}



sub code_header {
	return '
;do { # graphite code block
my $output = "";
'
}

sub code_tail {
	return '
;echo $output;
}; # end of graphite code
'
}

sub compile_text {
	my ($self, $text) = @_;

	return '' if $text =~ /\A\s*\Z/m;

	$text =~ s/\A\s+/ /m;
	$text =~ s/\A\s+</</m;
	$text =~ s/\s+\Z/ /m;
	$text =~ s/>\s+\Z/>/m;

	my $code = ";\n";

	my $value_regex = qr/
		\$[a-zA-Z0-9_]+| # variable
		\d+| # numeric value
		'[^']*'| # string
		"[^"]*" # string
		/msx;
	while ($text =~ /\G
			(\$[a-zA-Z0-9_]+)|
			\@(\$[a-zA-Z0-9_]+|[a-zA-Z0-9_]+(?:::[a-zA-Z0-9_]+)*)(?:->(?:
				($value_regex)|
				\[\s*((?:$value_regex(?:\s*,\s*$value_regex)*\s*(?:,\s*)?)?)\]|
				\{\s*((?:[a-zA-Z0-9_]+\s*=>\s*$value_regex(?:\s*,\s*[a-zA-Z0-9_]+\s*=>\s*$value_regex)*\s*(?:,\s*)?)?)\}
			))?|
			(.*?((?=[\$\@])|\Z))
			/msgx) {
		my ($var, $inc, $inc_val, $inc_list, $inc_hash, $html) = ($1, $2, $3, $4, $5, $6);
		if (defined $var) {
			$code .= "\n;\$output .= ". $self->compile_inc_val($var) .";\n";
		} elsif (defined $inc) {
			if ($inc =~ /\A\$/) {
				$inc = $self->compile_inc_val($inc);
			} else {
				$inc = "'$inc'";
			}
			if (defined $inc_val) {
				$code .= "\n;\$output .= \$graphite->render_template($inc => ". $self->compile_inc_val($inc_val) .");\n";
			} elsif (defined $inc_list) {
				$code .= "\n;\$output .= \$graphite->render_template($inc => ". $self->compile_inc_list($inc_list) .");\n";
			} elsif (defined $inc_hash) {
				$code .= "\n;\$output .= \$graphite->render_template($inc => ". $self->compile_inc_hash($inc_hash) .");\n";
			} else {
				$code .= "\n;\$output .= \$graphite->render_template($inc);\n";
			}
		} else {
			$html =~ s/\A\s+/ /m;
			$html =~ s/\s+\Z/ /m;
			$html =~ s#\\#\\\\#g;
			$html =~ s#'#\\'#g;
			next if $html =~ /\A\s*\Z/m;
			$code .= "\n;\$output .= '$html';\n";
		}
	}
	return $code
}

sub compile_inc_val {
	my ($self, $val) = @_;
	if ($val =~ /\A\$([a-zA-Z0-9_]+)\Z/) {
		my $name = $1;
		if ($name ne '_') {
			return "\$arg->{$name}";
		} else {
			return '$arg';
		}
	} elsif ($val =~ /\A\d+\Z/) {
		return $val;
	} elsif ($val =~ /\A'[^']*'\Z/) {
		return $val;
	} elsif ($val =~ /\A"([^"]*)"\Z/) {
		return "'$1'";
	} else {
		die "unknown value to compile: '$val'";
	}
}

sub compile_inc_list {
	my ($self, $text) = @_;

	my $code = '';
	if ($text eq '') {
		$code .= '[]';
	} else {
		$code .= '[';

		my $value_regex = qr/
			\$[a-zA-Z0-9_]+| # variable
			\d+| # numeric value
			'[^']*'| # string
			"[^"]*" # string
			/msx;
		while ($text =~ /\G\s*($value_regex)\s*(,\s*)?/msg) {
			my ($val, $cont) = ($1, $2);
			$code .= $self->compile_inc_val($val) . ', ';
			last unless defined $cont;
		}

		$code .= ']';
	}

	return $code
}

sub compile_inc_hash {
	my ($self, $text) = @_;

	my $code = '';
	if ($text eq '') {
		$code .= '{}';
	} else {
		$code .= '{';

		my $value_regex = qr/
			\$[a-zA-Z0-9_]+| # variable
			\d+| # numeric value
			'[^']*'| # string
			"[^"]*" # string
			/msx;
			# [a-zA-Z0-9_]+\s*=>\s*$value_regex
		while ($text =~ /\G\s*([a-zA-Z0-9_]+)\s*=>\s*($value_regex)\s*(,\s*)?/msg) {
			my ($key, $val, $cont) = ($1, $2, $3);
			$code .= "'$key' => " . $self->compile_inc_val($val) . ', ';
			last unless defined $cont;
		}

		$code .= '}';
	}
	return $code
}






# graphite helper functions

sub helper_template {
	my ($helper, $engine, $text) = @_;

	$text =~ s/\A([a-zA-Z0-9_]+(?:::[a-zA-Z0-9_]+)*)\s+?//ms or die '"template" helper requires a text name at start';
	my $name = $1;

	my $code =
"
;\$graphite->set_template('$name' => Carbon::Graphite::Template->new( sub {
my (\$self, \$graphite, \$arg) = \@_;
my \$output = '';
";
	$code .= $engine->compile_graphite ($text);
	$code .=
'
;return $output
}));
';
	return $code
}


sub helper_foreach {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A(\$[a-zA-Z0-9_]+)\b//ms or die '"foreach" helper requires variable name at start';
	my $name = $1;
	$name = $engine->compile_inc_val($name);
	my $code =
"
;foreach my \$arg (\@{$name}) {
";
	$code .= $engine->compile_graphite ($text);
	$code .= "\n}\n";

	return $code
}


sub helper_if {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*\(([^)]*)\)//ms or die '"if" helper requires a condition at start';
	my $condition = $1;

	$condition =~ s/(\$[a-zA-Z0-9_]+)\b/$engine->compile_inc_val($1)/e;
	my $code =
"
;\$graphite->condition_else(1);
if ($condition) {
";

	$code .= $engine->compile_graphite ($text);
	$code .= 
"
;\$graphite->condition_else(0);
}
";

	return $code
}

sub helper_elsif {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*\(([^)]*)\)//ms or die '"elsif" helper requires a condition at start';
	my $condition = $1;

	$condition =~ s/(\$[a-zA-Z0-9_]+)\b/$engine->compile_inc_val($1)/e;
	my $code =
"
;if (\$graphite->condition_else and ($condition)) {
";

	$code .= $engine->compile_graphite ($text);
	$code .= 
"
;\$graphite->condition_else(0);
}
";

	return $code
}

sub helper_else {
	my ($helper, $engine, $text) = @_;

	my $code =
"
;if (\$graphite->condition_else) {
";

	$code .= $engine->compile_graphite ($text);
	$code .= 
"
}
";

	return $code
}


sub helper_with {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A(\$[a-zA-Z0-9_]+)\b//ms or die '"with" helper requires variable name at start';
	my $name = $1;
	$name = $engine->compile_inc_val($name);
	my $code =
"
;do {
my \$arg = $name;
";
	$code .= $engine->compile_graphite ($text);
	$code .= "\n}\n";

	return $code
}


sub helper_namespace {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A([a-zA-Z0-9_]+(?:::[a-zA-Z0-9_]+)*)\b//ms or die '"namespace" helper requires namespace name at start';
	my $name = $1;
	my $code =
"
;\$graphite->push_namespace('$name');
";
	$code .= $engine->compile_graphite ($text);
	$code .= 
"
;\$graphite->pop_namespace;
";

	return $code
}

1;

