package App::FedoraPack::cli;

use 5.010;
use mro 'c3';
use strict;
use warnings;

use Archive::Tar ();
use Archive::Tar::Constant qw(SYMLINK DIR);
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Spec::Functions qw(abs2rel rel2abs catfile);
use IO::Compress::Gzip ();

use App::FedoraPack::System ();

our $VERSION = '0.7.0';


my ($sys, $sysver);


sub usage {
	my ($cls, $err) = @_;
	my $code = 0;

	if (defined $err) {
		select(STDERR);
		$code = 2;

		print $err, "\n\n";
	}

	my $name = basename($0);
	print <<USAGE;
Usage: $name --system-SYS=VER [features ...]

Please see 'perldoc $name' for more information on available features
and options.

USAGE

	exit $code;
}

sub version {
	my $name = basename($0);
	print "$name version $::VERSION\n";
	exit(0);
}


sub parse_sysver {
	my ($cls, $s, $v) = @_;

	$cls->usage("Multiple systems specified: $sys and $s") if defined $sys;
	$cls->usage("$s requires a version") unless defined $v;
	$cls->usage("Unknown system $s") unless App::FedoraPack::System->is_system($s);
	$cls->usage("Unknown version $v for system $s") unless App::FedoraPack::System->is_system_version($s, $v);

	($sys, $sysver) = ($s, $v);
}

sub parse_cmdline {
	my ($cls, $argv, $out_fh_ref) = @_;
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
		$cls->usage() if /^help$/i || $_ eq '?';
		$cls->version() if /^version$/;
		$cls->parse_sysver($1, $arg), next if /^system-([a-z0-9]+)$/;
		if (/^save-as$/) {
			$cls->arg_error("--save-as requires an argument") unless defined $arg;
			open(my $ofh, '>:utf8', $arg) or die "Can't open save-as file $arg: $^E";
			$$out_fh_ref = $ofh;
			next;
		}
		if (/^exec$/) {
			$cls->usage("--exec requires an argument") unless defined $arg;
			push(@scripts, $arg);
			next;
		}
		# defer all feature processing so the System object can do it
		push(@features, [ $_, $arg ]);

	} continue {
		# advance pointer
		$ptr += $inc;
	}

	$cls->usage("No system specified") unless defined $sys;
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
	$cls->usage("No directory given to bundle") unless @ARGV;
	my $dirset = {};
	for my $dir (@ARGV) {
		$cls->usage("Not a directory, can't bundle: $dir") unless -d $dir;

		my $bn = basename($dir);
		# instead of 'pack/*', let's bundle everything at the toplevel and reserve
		# /_* for any metadata we may want to add in the future.
		$cls->usage("Underscore prefix is reserved ($bn), can't add $dir") if $bn =~ /^_/;
		$cls->usage("Basename collision: $bn already bundled, can't add $dir") if $dirset->{$bn};
		$dirset->{$bn} = 1;
	}
	$rv->add_targets(@ARGV);

	# set scripts
	$cls->usage("No target (post-install) scripts specified") unless @scripts;
	$rv->add_target_scripts(@scripts) if @scripts;

	return $rv;
}



sub get_guest_sh_in {
	return <<'GUEST_SH';
#!/usr/bin/env bash
[ -z $FEDORAPACK_DEBUG ] || set -x
set -e

FEDORAPACK_TAR_DIR="/var/local/fedora-pack"

# find ourselves
self_file="$0"
[ -e "$self_file" ] || self_file="$(command -v "$self_file" 2>/dev/null)"
cut_line=$(( `grep -an '^#END_STAGE1$' "$self_file" | cut -d: -f1` + 1 ))
if [ "$cut_line" -le 1 ] ; then
	echo "Cannot find '#END_STAGE1' line - extraction failed" >&2
	exit 1
fi

# make absolute
[ "$(echo "$self_file" | cut -c1)" == / ] || \
	self_file="$(pwd -P)/$self_file"

# exec payloads in workdir
sudo install -d -m 0700 -o `id -un` -g `id -gn` "$FEDORAPACK_TAR_DIR"
cd "$FEDORAPACK_TAR_DIR"
@PACKAGE_SCRIPT@

tail -n +$cut_line "$self_file" | tar zxf -
export FEDORAPACK_TAR_DIR
@RUNNER_SCRIPTS@

# Magic token so that we don't hardcode any line-numbers.
#END_STAGE1
GUEST_SH
}

sub quote_cmdline {
	my ($cls, $cmd) = @_;
	my @out = ();
	for (@$cmd) {
		s/'/'\\''/g;
		push(@out, "'$_'");
	}

	return join(' ', @out);
}

sub generate_guest_stub {
	my ($cls, $sys, $out_fh) = @_;
	my $guest_sfx = $cls->get_guest_sh_in();

	{ my $inst = $sys->make_install;
		$guest_sfx =~ s/\@PACKAGE_SCRIPT\@/$inst/g; }

	{ my $cmds = $sys->get_target_script_cmds;
		my $txt = join("\012", map { $cls->quote_cmdline($_) } @$cmds);
		$guest_sfx =~ s/\@RUNNER_SCRIPTS\@/$txt/g; }

	$out_fh->print($guest_sfx);
}

sub generate_tarball {
	my ($cls, $sys, $out_fh) = @_;
	my $dirs = $sys->get_target_dirs();

	# set up gzip stream on output
	binmode($out_fh, ':raw');
	my $gz_fh = IO::Compress::Gzip->new($out_fh, -Level => 9)
		or die "GZip error while opening stream: $IO::Compress::Gzip::GzipError";

	# write tar bundle into gzip stream (into output);
	# tar formed like "cd `dirname $bundle_root` && tar zcf - $bundle_root"
	my $tar = Archive::Tar->new();

	for my $bundle_rel (@$dirs) {
		my $bundle_root = rel2abs($bundle_rel);

		my $add_tar_file = sub {
			return unless -f $_ || -d _ || -l _;

			local $/; # slurp
			my $fh;
			my $rel_file = abs2rel($_, dirname($bundle_root));
			if (-l $_) {
				unless (-f _ || -d _) {
					# target cannot possibly be added
					warn "skipping non-file/directory symlink to provisioner: $_";
					return;
				}
				$tar->add_data($rel_file, readlink $_, { type => SYMLINK })
					or warn "Adding symlink $_ to provisioner: ".$tar->error;
			} elsif (-d _) {
				$tar->add_data($rel_file, '', { type => DIR });
			} elsif (-z _) {
				$tar->add_data($rel_file, '', { size => 0 });
			} elsif (open($fh, '<:raw', $_)) {
				$tar->add_data($rel_file, <$fh>)
					or die "Adding file $rel_file to provisioner: ".$tar->error;
				close $fh;
			} else {
				warn "skipping adding $_ to provisioner due to open error: $^E";
			}
		};
		find({ wanted => $add_tar_file, no_chdir => 1 }, $bundle_root);
	}

	# Finalize tar/gzip data
	$tar->write($gz_fh);
	undef $tar;
	# old Archive::Tar's always closed their handle
	if (! ($Archive::Tar::VERSION =~ /^1\.\d{2}$/ && $Archive::Tar::VERSION < 1.60)) {
		close($gz_fh) or warn "Closing gzip handle: $!";
	}
}

sub generate_provisioner {
	my ($cls, $sys, $out_fh) = @_;

	binmode($out_fh, ':unix:utf8');
	$cls->generate_guest_stub($sys, $out_fh);
	$cls->generate_tarball($sys, $out_fh);
}


sub main {
	my ($cls, $argv) = @_;
	my $out_fh = \*STDOUT;
	my $sys = $cls->parse_cmdline($argv, \$out_fh);

	$cls->generate_provisioner($sys, $out_fh);
}

1;
