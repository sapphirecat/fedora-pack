package System::AmazonLinux;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use base qw(System::Fedora);
__PACKAGE__->register('amazon', [ qw(2014.09) ]);
__PACKAGE__->register_feature('epel', 'enable_epel');

sub _provides_perl {
	return 5.16;
}


sub _provides_php {
	return 5.5; # highest version in repo
}

sub _pkgs_php {
	return [ qw(php55-cli) ];
}


sub _provides_python2 {
	return 2.7;
}

sub _pkgs_python2 {
	return [ qw(python27 python27-pip) ];
}

sub feature_python2 {
	my $self = shift;
	$self->add_scripts('sudo pip install virtualenv');
	$self->SUPER::feature_python2(@_);
}


sub _provides_python3 {
	return 0;
}


sub enable_epel {
	my ($self) = @_;
	my $script = <<'BASH';
out=`mktemp -t "epel-$$-XXXXXXXX.repo"`
awk -F= </etc/yum.repos.d/epel.repo >"$out" '
	BEGIN { in_epel=0 }
	/^\[/ { in_epel=0 }
	/^\[epel\]/ { in_epel=1 }
	in_epel=1 && $1 == "enabled" { $0="enabled=1" }
	1'
sudo cp "$out" /etc/yum.repos.d/epel.repo
BASH
	$self->add_pre_scripts($script);
}

1;
