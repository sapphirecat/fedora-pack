package App::FedoraPack::System::Fedora;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use base qw(App::FedoraPack::System);
__PACKAGE__->register('fedora', [ qw(20 21) ]);

sub _provides_perl {
	my ($self) = @_;

	return 5.20 if $self->{version} >= 21;
	return 5.18;
}

sub _pkgs_perl {
	return [ qw(perl perl-core perl-App-cpanminus perl-local-lib) ];
}

sub feature_perl {
	my $self = shift;
	$self->add_scripts('cpanm -n -S carton');
	$self->SUPER::feature_perl(@_);
}


sub _provides_php {
	my ($self) = @_;

	return 5.6 if $self->{version} >= 21;
	return 5.5;
}

sub _pkgs_php {
	return [ qw(php-cli) ];
}


sub _provides_python2 {
	return 2.7;
}

sub _pkgs_python2 {
	return [ qw(python python-virtualenv python-pip) ];
}

sub _provides_python3 {
	my ($self) = @_;

	return 3.4 if $self->{version} >= 21;
	return 3.3;
}

sub _pkgs_python3 {
	return [ qw(python3 python3-pip) ];
}

1;
