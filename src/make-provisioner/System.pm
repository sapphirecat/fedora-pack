package System;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use List::Util qw(max);

my $sys = {};
my $feature = {};

# Given a system and versions it handles, register the invoked module as
# providing them all.  Called in System::X as __PACKAGE__->register().
sub register {
	my ($cls, $name, $versions_aref) = @_;
	die q{Call __PACKAGE__->register($name, \\@versions) while loading a System subclass} if ref $cls;
	for my $v (@$versions_aref) {
		$sys->{$name}{$v} = $cls;
	}

	return $cls;
}

sub is_system {
	return exists($sys->{$_[1]});
}

sub is_system_version {
	return exists($sys->{$_[1]}) && exists($sys->{$_[1]}{$_[2]});
}

# Return all registered systems for command-line parsing.
sub get_systems {
	return [ keys %$sys ];
}

# Return the registered versions for a given system.
sub get_versions {
	my $copy = {};
	for my $n (keys %$sys) {
		$copy->{$n} = [ keys %{ $sys->{$n} } ];
	}
	return $copy;
}

# Resolve a (system, version) pair to a registered module name.
sub get_module {
	my ($cls, $s_name, $version) = @_;
	die "No such system: $s_name" unless $sys->{$s_name};

	$version ||= max(keys %{$sys->{$s_name}});

	if (my $mod = $sys->{$s_name}{$version}) {
		return $mod;
	}

	die "No such version for system $s_name: $version";
}

# Given the (system, version) args, find the module registered for it, and
# build an instance of that module.
sub get_new {
	my ($cls, @args) = @_;
	return $cls->get_module(@args)->new(@args);
}


sub register_feature {
	my ($mod, $name, $handler) = @_;

	die "Feature already registered: $name" if exists $feature->{$name};
	$feature->{$name} = $handler;

	return $mod;
}

sub is_feature {
	return exists($feature->{$_[1]});
}

sub get_features {
	return [ keys %$feature ];
}


# Return a new object recording the (system, version) args -- normally, the
# values passed to get_new that resolved the System::* module being called
# here.  (Sorry, it's weird.)
#
# tl;dr: use System->get_new() instead of this if possible.
sub new {
	my ($mod, $s_name, $version) = @_;
	my $self = {
		system => $s_name,
		version => $version,
		pre_scripts => [],
		packages => [],
		scripts => [],
	};
	bless $self, $mod;
}

# Add to the list of packages to install from the package manager
sub add_installs {
	my ($self, @items) = @_;
	push(@{ $self->{packages} }, @items);
}

# Add to the list of bash commands to run after the package manager
sub add_scripts {
	my ($self, @items) = @_;
	push(@{ $self->{scripts} }, @items);
}

sub add_pre_scripts {
	my ($self, @items) = @_;
	unshift(@{ $self->{pre_scripts} }, @items);
}

# Convert installs and scripts to bash commands (running as user)
sub make_install {
	my ($self) = @_;
	return join("\n",
		@{ $self->{pre_scripts} },
		$self->make_install_cmd($self->{packages}),
		@{ $self->{scripts} },
		"\n"
	);
}

# Given a (name, version_provided, version_wanted, package_list_aref), checks
# that the version_wanted does not exceed version_provided, then requests
# installation of the package_list_aref.  Dies (using name in the error) if
# the version check fails.
sub _add_install_version {
	my ($self, $name, $v_avail, $v_want, $pkgset) = @_;
	if ($v_avail < $v_want) {
		die "$name: requested version $v_want but system only has $v_avail";
	}
	$self->add_installs(@$pkgset);
}

# 'protected': given a name and version wanted, call _provides_name and
# _pkgs_name to find the version provided and package list; then, install the
# packages if the version requirement is met.  Returns the name as the binary
# to invoke the main interpreter of the package; or if given an optional
# binary, returns that instead.
sub _installer {
	my ($self, $name, $want_version, $binary) = @_;
	$binary = $name unless defined $binary;

	my ($provides, $packages) = ("_provides_$name", "_pkgs_$name");
	$self->_add_install_version($name, $self->$provides, $want_version,
		$self->$packages);

	return $binary;
}


# Install composer via shell commands
# TODO: have an option to use pre-downloaded composer.phar
sub add_php_composer {
	my ($self) = @_;
	my $script = <<SHELL;
php -r "readfile('https://getcomposer.org/installer');" | php
sudo install -m 0755 -o root -g root composer.phar /usr/bin/composer
SHELL
	$self->add_scripts($script);
}


sub feature_bash {
	# Considered essential in Debian, default in Fedora; nothing to install
	return 'bash';
}

sub feature_perl {
	my ($self, $version) = @_;
	$self->_installer(perl => $version);
}

sub feature_php {
	my ($self, $version) = @_;
	my $rv = $self->_installer(php => $version);
	$self->add_php_composer;
}

sub feature_python2 {
	my ($self, $version) = @_;
	$self->_installer(python2 => $version, 'python');
}

sub feature_python3 {
	my ($self, $version) = @_;
	$self->_installer(python3 => $version);
}

1;
