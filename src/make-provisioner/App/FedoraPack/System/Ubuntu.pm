package App::FedoraPack::System::Ubuntu;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use base qw(App::FedoraPack::System::Debian);
__PACKAGE__->register('ubuntu', [ qw(14.04 trusty 14.10 utopic) ]);

sub new {
	my $mod = shift;
	my $self = $mod->SUPER::new(@_);

	return $self unless $self->{system} eq 'ubuntu';

	# normalize version
	if ($self->{version} !~ /^[.\d]+$/) {
		$self->{version} = '14.04' if $self->{version} eq 'trusty';
		$self->{version} = '14.10' if $self->{version} eq 'utopic';
	}

	if ($self->{version} !~ /^\d{2}\.\d{2}$/) {
		die "Unrecognized Ubuntu version: $self->{version}"
	}

	return $self;
}


sub _provides_perl {
	my ($self) = @_;

	return 5.20 if $self->{version} >= 14.10;
	return 5.18;
}

sub _provides_php {
	my ($self) = @_;

	return 5.5;
}

sub _provides_python2 {
	return 2.7;
}

sub _provides_python3 {
	return 3.4;
}

1;
