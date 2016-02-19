package Carbon::Anthracite::HTMLParser;
use strict;
use warnings;

use feature 'say';



# a simple html parser which parses out tags, text, and directives


sub new {
	my ($class, $text) = @_;
	my $self = bless { text => $text, complete => 0 }, $class;

	return $self
}


# parses text and returns the next token in text or undef if parsing is done
# token is a list describing the token, the first value being the type of token
sub get_token {
	my ($self) = @_;

	# don't restart parsing after we've already completed it
	return if $self->{complete};

	# get a token from text
	while ($self->{text} =~
			m/\G
				(<([!\/]?[a-zA-Z]+\b)(.*?)>)| # match a start tag, end tag, or comment
				(<\?([a-zA-Z]+)(.*?)(?:\?>|\Z(?!\s)))| # match a directive
											# this is a fix for some inexplicable behavior where the 
											# \Z will match on the newline before the end of the string
				(.+?)(?:(?=<)|\Z) # match regular text
			/smxg) {
		my ($tag, $tag_type, $tag_data, $directive, $directive_type, $directive_data, $text) = ($1, $2, $3, $4, $5, $6, $7);

		# parse the result
		if (defined $tag) {
			return tag => $tag, $tag_type, $tag_data
		} elsif (defined $directive) {
			return directive => $directive, $directive_type, $directive_data
		} else {
			return text => $text
		}
	}
	# since the regex stopped matching, we have completed the search and should not return
	$self->{complete} = 1;

	return
}


1;

