package App::FedoraPack::System;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Spec::Functions qw(catfile splitpath splitdir abs2rel file_name_is_absolute);
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
# values passed to get_new that resolved the App::FedoraPack::System::* module
# being called here.  (Sorry, it's weird.)
#
# tl;dr: use App::FedoraPack::System->get_new() instead of this.
sub new {
	my ($mod, $s_name, $version) = @_;
	my $self = {
		system => $s_name,
		version => $version,
		# for generating paths for the *target* system to interpret, see our
		# host_catfile etc. methods
		filespec => 'File::Spec::Unix',

		pre_scripts => [],
		packages => [],
		scripts => [],
		binaries => {},

		targets => [],
		target_scripts => [],

		enabled => {}, # enabled languages/features/etc.
	};
	bless $self, $mod;
}

sub _add {
	my ($self, $kind, @items) = @_;
	push(@{ $self->{$kind} }, @items);
	return $self;
}

# Add a directory to bundle
sub add_targets {
	my $self = shift;
	$self->_add('targets', @_);
}


# Add to the list of packages to install from the package manager
sub add_installs {
	my $self = shift;
	$self->_add('packages', @_);
}

# Add to the list of bash commands to run after the package manager
sub add_scripts {
	my $self = shift;
	$self->_add('scripts', @_);
}

# add scripts to run before the package manager
sub add_pre_scripts {
	my $self = shift;
	unshift(@{ $self->{pre_scripts} }, @_); # not _add(): we don't want to push()
}


sub host_catfile {
	my $self = shift;
	$self->{filespec}->catfile(@_);
}

sub host_catdir {
	my $self = shift;
	$self->{filespec}->catdir(@_);
}

sub splitpath_and_dirs {
	my ($self, $thing, $no_file) = @_;

	my ($vol, $path, $file) = splitpath($thing, $no_file);
	my (@dirs) = splitdir($path);
	# splitpath doesn't yield clean paths, confusing splitdir... drop any
	# `undef` entries from the resulting array
	@dirs = map { $_ // () } @dirs;

	return ($vol, [ @dirs ], $file);
}


# Locate a script within a target directory; the script may be given as
# relative to the target; or, if the path resolves within the target, as
# relative to CWD or as an absolute path.  Returns two values: the target dir,
# and the path relative to it.
sub resolve_target_script {
	my ($self, $script) = @_;

	die "Cannot resolve script $script without bundle dir set" unless @{ $self->{targets} };

	my $is_valid = sub {
		return 0 if file_name_is_absolute($_[0]);
		return -e catfile($_[1], $_[0]);
	};
	for my $rootpath (@{ $self->{targets} }) {
		# If it's already relative to the root, return it immediately.
		return ($rootpath, $script) if $is_valid->($script, $rootpath);

		# See if it's an absolute path or relative-to-CWD path that points into
		# the root.  If so, return the relative-to-the-root conversion of it.
		my $rel_script = abs2rel($script, $rootpath);
		return ($rootpath, $rel_script) if $is_valid->($rel_script, $rootpath);
	}

	# Try to give out unambiguous (if possibly confusing) diagnostics.
	die "Script $script seems to be outside of bundle dir" if -e $script;
	die "Cannot resolve script $script relative to bundle dir or CWD";
}

# From a script filename, guess its language
sub resolve_script_lang {
	my ($self, $file, $in_dir) = @_;

	return 'perl' if $file =~ /\.pl$/;
	return 'php' if $file =~ /\.ph(?:p|ar)$/; # php|phar
	return 'bash' if $file =~ /\.(?:ba)?sh$/; # bash|sh
	# TODO: use $in_dir to guess based on the script content (e.g. shebang)
	return 'python2' if $file =~ /\.py$/;
}

# Generate a [ $interpreter, @options, $tarball_path ] for the given language,
# script, and root_dir.  Dies on unknown languages or unacceptable scripts.
sub cmdline_for_script {
	my $self = shift;
	my ($lang, $script, $root_dir) = @_;
	my ($basedir, $bin);

	my ($vol, $dirs, $file) = $self->splitpath_and_dirs($root_dir, 1);
	$basedir = scalar @$dirs ? pop @$dirs : 'NO_DIRS_WTF';
	($vol, $dirs, $file) = $self->splitpath_and_dirs($script);

	$bin = $self->{binaries}{$lang};
	die "No binary loaded for language $lang" unless $bin;

	if ($lang =~ /^python/ && -d catdir($root_dir, $script)) {
		return [ $bin, $self->host_catdir($basedir, @$dirs, $file) ] if -e catfile($root_dir, $script, '__main__.py');
	} elsif (-f catfile($root_dir, $script)) {
		return [ $bin, $self->host_catfile($basedir, @$dirs, $script) ];
	}
}

# Add programs to run in target directory
sub add_target_scripts {
	my $self = shift;
	my @scripts;

	for my $script (@_) {
		my ($lang, $in_dir, $relscript, $cmd);

		if ($script =~ /^(\w+),(.*)$/) {
			$lang = $1;
			$script = $2;
		}

		($in_dir, $relscript) = $self->resolve_target_script($script);
		$lang ||= $self->resolve_script_lang($relscript, $in_dir);

		my $addlang = "feature_$lang";
		$self->$addlang() unless $self->{enabled}{$lang};
		my $cmdline = $self->cmdline_for_script($lang, $relscript, $in_dir);
		push(@scripts, $cmdline);
	}

	$self->_add('target_scripts', @scripts);
}


# Convert installs and scripts to bash commands (running as user)
sub make_install {
	my ($self) = @_;
	return join("\n",
		@{ $self->{pre_scripts} },
		$self->make_install_cmd($self->{packages}),
		@{ $self->{scripts} },
	);
}

sub get_target_dirs {
	$_[0]->{targets};
}

sub get_target_script_cmds {
	$_[0]->{target_scripts};
}

# Given a (name, version_provided, version_wanted, package_list_aref), checks
# that the version_wanted does not exceed version_provided, then requests
# installation of the package_list_aref.  Dies (using name in the error) if
# the version check fails.
sub _add_install_version {
	my ($self, $name, $binary, $v_avail, $v_want, $pkgset) = @_;
	if (defined($v_want) && $v_avail < $v_want) {
		die "$name: requested version $v_want but system only has $v_avail";
	}
	$self->{binaries}{$name} = $binary;
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
	$self->_add_install_version($name, $binary, $self->$provides, $want_version,
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
	my ($self) = shift;
	# Considered essential in Debian, default in Fedora; nothing to install
	$self->{binaries}{bash} ||= 'bash';
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
	return $rv;
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
