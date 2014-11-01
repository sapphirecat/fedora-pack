package cli;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use File::Basename qw(basename);

use System ();

our $VERSION = '0.7.0'; # SemVer

# Path to bundled files in the self-extractor's tarball.  In the future, we
# MAY pack additional data for the self-extractor to use without risk of our
# new names clashing with entries inside the user's bundle directory.
our $TAR_TOPLEVEL_DIR = 'pack';


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


sub parse_sysver {
	my ($s, $v) = @_;

	usage "Multiple systems specified: $sys and $s" if defined $sys;
	usage "$_ requires a version" unless defined $v;
	usage "Unknown system $s" unless System->is_system($s);
	usage "Unknown version $v for system $s" unless System->is_system_version($s, $v);

	($sys, $sysver) = ($s, $v);
}

sub parse_feature {
	# TODO
}


sub parse_cmdline {
	my ($argv) = @_;
	my (@features);
	my ($ptr, $max) = (0, $#$argv);
	while ($ptr <= $max) {
		my ($inc, $arg) = (2);
		$_ = $argv->[$ptr];
		$arg = $argv->[$ptr + 1] if $ptr < $max;

		# hit a non-option
		if ($_ eq '--' || ! /^--/) {
			++$ptr;
			last;
		}

		s/^--//;
		if (/^([-a-z0-9]+)=(.*)$/) {
			($inc, $_, $arg) = (1, $1, $2);
		}

		$ptr += $inc;

		usage() if /^help$/i;
		version() if /^version$/;
		parse_sysver($1, $arg) if /^system-([a-z0-9]+)$/;
		# defer all feature processing so the system can do it
		push(@features, [ $_, $arg ]);
	}

	my $rv = System->get_new($sys, $sysver);

	# perform deferred feature processing via the system
	for my $feat_desc (@features) {
		my ($feat, $arg) = @$feat_desc;
		$feat =~ s/\W/_/g;
		$rv->$feat($arg) if $rv->is_feature($feat);
	}

	return $rv;
}


sub main {
	my $sys = parse_cmdline(\@::ARGV);
	$sys->something();
}

1;
