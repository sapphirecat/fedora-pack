package App::FedoraPack::System::Debian;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use base qw(App::FedoraPack::System);
__PACKAGE__->register('debian', [ qw(7 wheezy 8 jessie) ]);


sub new {
	my $mod = shift;
	my $self = $mod->SUPER::new(@_);

	return $self unless $self->{system} eq 'debian';

	# normalize version
	if ($self->{version} !~ /^\d+$/) {
		$self->{version} = 7 if $self->{version} eq 'wheezy';
		$self->{version} = 8 if $self->{version} eq 'jessie';
	}

	if ($self->{version} !~ /^\d+$/) {
		die "Unrecognized Debian version: $self->{version}";
	}

	return $self;
}


sub make_install_cmd {
	my ($self, $pkgset) = @_;
	return join("\n",
		'export DEBIAN_FRONTEND=noninteractive',
		# Ubuntu doesn't keep security updates at time T on mirrors forever, so if
		# we have an AMI built at T, and ask to install stuff, it may not be
		# possible (without this update) if a stale security update is the latest
		# in the local cache.  (This actually did happen to me once.)
		'sudo apt-get -q -y update',
		# install through aptitude so we can use -R (--without-recommends)
		'command -v aptitude >/dev/null 2>&1 || sudo apt-get -q -y install aptitude',
		"sudo aptitude -q -y -R install @$pkgset",
	);
}


sub _provides_perl {
	my ($self) = @_;

	return 5.20 if $self->{version} >= 8;
	return 5.14;
}

sub _pkgs_perl {
	return [ qw(perl cpanminus liblocal-lib-perl carton) ];
}


sub _provides_php {
	my ($self) = @_;

	return 5.6 if $self->{version} >= 8;
	return 5.4;
}

sub _pkgs_php {
	return [ qw(php5-cli curl php5-curl) ];
}


sub _provides_python2 {
	return 2.7;
}

sub _pkgs_python2 {
	my ($self) = @_;
	my $venv = $self->{version} >= 8 ? 'virtualenv' : 'python-virtualenv';
	return [ qw(python python-pip), $venv ];
}

sub _provides_python3 {
	my ($self) = @_;
	return 3.4 if $self->{version} >= 8;
	return 3.2;
}

sub _pkgs_python3 {
	my ($self) = @_;
	my $venv = $self->{version} >= 8 ? 'virtualenv' : 'python3-virtualenv';
	return [ qw(python3 python3-pip), $venv ];
}

1;
