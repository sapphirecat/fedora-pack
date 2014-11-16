package App::FedoraPack::cli;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use File::Basename qw(basename);

use App::FedoraPack::System ();

our $VERSION = '0.7.0'; # SemVer
# 1-arg sub invoked on usage errors in parse_cmdline.  Its return value is
# passed back out of parse_cmdline in place of the System object.  If not set
# to a CODE ref, usage() is invoked instead, which will call exit().
our $ERR_HANDLER;


my ($sys, $sysver);


sub usage (;$) {
	my ($err) = @_;
	my $code = 0;

	if (defined $err) {
		select(STDERR);
		$code = 2;

		print $err, "\n\n";
	}

	my $name = basename($0);
	print <<USAGE;
Usage: $name --system-SYS=VER [features ...]

TODO: more usage here.

USAGE

	exit $code;
}

sub version {
	my $name = basename($0);
	print "$name version $::VERSION\n";
	exit(0);
}


# "usage die" -- allows for intercepting usage() calls from parse_cmdline(),
# for callers to handle errors if they set $ERR_HANDLER.
sub udie ($) {
	return $ERR_HANDLER->(shift) if $ERR_HANDLER && ref $ERR_HANDLER eq 'CODE';
	usage(shift);
}


sub parse_sysver {
	my ($s, $v) = @_;

	usage "Multiple systems specified: $sys and $s" if defined $sys;
	usage "$s requires a version" unless defined $v;
	usage "Unknown system $s" unless App::FedoraPack::System->is_system($s);
	usage "Unknown version $v for system $s" unless App::FedoraPack::System->is_system_version($s, $v);

	($sys, $sysver) = ($s, $v);
}


sub parse_cmdline {
	my ($argv) = @_;
	my (@features, @scripts);

	# We want dynamic options (--system-f is valid if System::F is loadable), so
	# we parse them ourselves instead of using Getopt::Long.
	my ($ptr, $max, $inc) = (0, $#$argv);
	while ($ptr <= $max) {
		my $arg;
		$_ = $argv->[$ptr];
		$inc = 1; # number of arguments to consume
		($inc, $arg) = (2, $argv->[$ptr + 1]) if $ptr < $max;

		# hit a non-option
		if ($_ eq '--') {
			++$ptr; # move past explicit end-of-options flag
			last;
		} elsif (! /^--/) {
			last;
		}

		# parse --option[=value] -> option in $_, value in $arg, $inc reduced if
		# this option had the value bundled in.
		s/^--//;
		if (/^([-a-z0-9]+)=(.*)$/) {
			($inc, $_, $arg) = (1, $1, $2);
		} elsif ($arg =~ /^--/) {
			($inc, $arg) = (1);
		}

		# parse actual option/arg pair
		usage() if /^help$/i || $_ eq '?';
		version() if /^version$/;
		parse_sysver($1, $arg), next if /^system-([a-z0-9]+)$/;
		if (/^exec$/) {
			return udie "--exec requires an argument" unless defined $arg;
			push(@scripts, $arg);
			next;
		}
		# defer all feature processing so the System object can do it
		push(@features, [ $_, $arg ]);

	} continue {
		# advance pointer
		$ptr += $inc;
	}

	return udie "No system specified" unless defined $sys;
	my $rv = App::FedoraPack::System->get_new($sys, $sysver);

	# consume the arguments we have processed
	splice(@ARGV, 0, $ptr);

	# perform deferred feature processing via the System
	for my $feat_desc (@features) {
		my ($feat, $arg) = @$feat_desc;
		$feat =~ s/\W/_/g;
		my $feat_method = "feature_$feat";
		$rv->$feat_method($arg) if $rv->is_feature($feat);
	}

	# add in the bundle dirs
	return udie "No directory given to bundle" unless @ARGV;
	my $dirset = {};
	for my $dir (@ARGV) {
		return udie "Not a directory, can't bundle: $dir" unless -d $dir;

		my $bn = basename($dir);
		# instead of 'pack/*', let's bundle everything at the toplevel and reserve
		# /_* for any metadata we may want to add in the future.
		return udie "Underscore prefix is reserved ($bn), can't add $dir" if $bn =~ /^_/;
		return udie "Basename collision: $bn already bundled, can't add $dir" if $dirset->{$bn};
		$dirset->{$bn} = 1;
	}
	$rv->add_targets(@ARGV);

	# set scripts
	return udie "No target (post-install) scripts specified" unless @scripts;
	$rv->add_target_scripts(@scripts) if @scripts;

	return $rv;
}


sub main {
	my $sys = parse_cmdline(\@::ARGV);
	die "Command line parsed OK, but the rest is yet to come.\n";
	#$sys->something();
}

1;
