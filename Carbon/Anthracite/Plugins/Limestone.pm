package Carbon::Anthracite::Plugins::Limestone;
use parent 'Carbon::Anthracite::Plugin';
use strict;
use warnings;

use feature 'say';

use Carbon::Limestone::Client;


# simple plugin that provides an interface to an existing Limestone database

sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new;

	$self->hostport($args{hostport} // die "hostport required");
	$self->username($args{username} // die "username required");
	$self->password($args{password} // die "password required");

	return $self
}


sub hostport { @_ > 1 ? $_[0]{anthracite_plugin_limestone__hostport} = $_[1] : $_[0]{anthracite_plugin_limestone__hostport} }
sub client { @_ > 1 ? $_[0]{anthracite_plugin_limestone__client} = $_[1] : $_[0]{anthracite_plugin_limestone__client} }
sub username { @_ > 1 ? $_[0]{anthracite_plugin_limestone__username} = $_[1] : $_[0]{anthracite_plugin_limestone__username} }
sub password { @_ > 1 ? $_[0]{anthracite_plugin_limestone__password} = $_[1] : $_[0]{anthracite_plugin_limestone__password} }


sub init_thread {
	my ($self) = @_;
	$self->client(Carbon::Limestone::Client->new(hostport => $self->hostport, username => $self->username, password => $self->password));
}


sub code_header {
	my ($self, $data) = @_;
	return
'
our $limestone = $runtime->{anthracite_plugin_limestone__client};
'
}

sub create_runtime {
	my ($self, $compiled, $runtime) = @_;
	$runtime->{anthracite_plugin_limestone__client} = $self->client;
	return $runtime
}

1;

