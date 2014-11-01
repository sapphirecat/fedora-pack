#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use IO::File ();
use IO::Handle ();

use FindBin ();
use File::Spec::Functions qw(catdir catfile splitpath splitdir);
use lib catdir($FindBin::Bin, 'lib'); # for @ISA discovery


# mod_single = [ module, filename, depending_module_names ]


build_binaries('make-provisioner');


sub build_binaries {
	for my $bin (@_) {
		my $st = {
			loaded => {},
			deferred => {},
			order => [],
		};

		my $root_dir = catdir($FindBin::Bin, 'src', $bin);

		for my $mod_single (find_modules($root_dir)) {
			push(@$mod_single, find_depends($mod_single, $root_dir));
			resolve_load($st, $mod_single);
		}

		my $bin_name = catfile($FindBin::Bin, 'bin', $bin);
		open(my $fh, '>:utf8', $bin_name)
			or die "opening $bin_name for output: $^E";
		stream_modules($fh, catfile($root_dir, 'main.pl'), $st->{order});

		{
			no strict 'refs';
			my $pp = "postproc_$bin";
			$pp =~ s/\W+/_/g;
			$pp->($fh, $root_dir) if exists &$pp;
		}

		close $fh or die("close failed after writing $bin_name: $^E");
		exit 0;
	}
}


sub postproc_make_provisioner {
	my ($fh, $dir) = @_;

	# append the guest.sh script in the DATA filehandle
	$fh->print("\012__DATA__\012");
	copy_out($fh, catfile($dir, 'guest.sh'));
}


# simulate open(FOO, "-|") on win32, from `perlfork`
sub pipe_from_fork ($) {
	no strict 'refs'; # we take a string to open a global filehandle with
	my $parent = shift;
	pipe $parent, my $child or die;
	my $pid = fork();
	die "(pipe from) fork() failed: $!" unless defined $pid;
	if ($pid) {
		close $child;
	} else {
		close $parent;
		open(STDOUT, ">&=" . fileno($child)) or die;
	}
	$pid;
}

sub copy_out {
	my ($stream, $srcname) = @_;
	die "source filename required" unless $srcname;
	open(my $src, '<:utf8', $srcname) or die "opening $srcname for copy: $^E";
	my $ln;
	$stream->print($ln) while $ln = <$src>;
	close($src) or die "closing $srcname after copy: $^E";
	return $stream;
}

sub insert_module {
	my ($stream, $mod_single) = @_;
	my $mod = $mod_single->[0];

	# write each module into a fresh, limited lexical scope (so package lexicals
	# stay local to the package, not visible to end-of-file)
	$stream->print("{\n");

	# add this module into \%INC so that `use X` works from later ones, without
	# trying to load this one from the standard path.
	$stream->print(<<INCLUDE_HACK);
	BEGIN {
		my \$mod_tail = File::Spec->catfile(split(/::/, "$mod.pm"));
		\$::INC{\$mod_tail} = File::Spec->catfile(\$FindBin::Bin, \$mod_tail);
	}
INCLUDE_HACK

	# include the actual module contents
	copy_out($stream, $mod_single->[1]);

	# end that lexical scope we started
	$stream->print("}\n");
}

sub stream_modules {
	my ($stream, $scriptname, $modlist) = @_;
	open(my $scriptfh, '<:utf8', $scriptname) or die "opening $scriptname to merge modules: $^E";
	while (my $ln = <$scriptfh>) {
		if ($ln =~ /^#INSERT_PACKAGES#/) {
			$stream->print("BEGIN { require File::Spec; }");
			insert_module($stream, $_) for @$modlist;
		} else {
			$stream->print($ln);
		}
	}
	return $stream;
}


sub find_modules { # dir -> array:aref:module,filename
	# breadth-first: queue up dirs as we encounter them, then process in turn,
	# starting with the one that was passed in.
	my @nextdirs = ([shift(@_), '']);
	my @fileset = ();

	while (my $curinfo = shift @nextdirs) {
		my ($curdir, $scope) = @$curinfo;
		opendir(my $dh, $curdir) or die "Can't open $curdir: $^E";

		while (my $entry = readdir($dh)) {
			next if $entry =~ /^[._]/; # skip leading dot/underscore

			my $maybe_dir = catdir($curdir, $entry);
			if (-d $maybe_dir) {
				push(@nextdirs, [$maybe_dir, $scope . $entry . '::']);
			} elsif ($entry =~ /\.pm$/) {
				my $file = catfile($curdir, $entry);
				my $modname = $scope.$entry;
				$modname =~ s/\.pm$//;
				push(@fileset, [$modname, $file]) if -f $file;
			}
		}

		closedir($dh);
	}

	return @fileset;
}

sub find_depends { # mod_info -> aref:module_names
	# mod_single: 0=Module::Name, 1=/path/to/Module/Name.pm
	# our return value will become index 2
	my ($mod_single, $dir) = @_;
	my %old_mods = %INC;
	my %new_mods;

	if (my $pid = pipe_from_fork('MODLINK')) {
		# parent: read from child
		my $buf;
		local $/ = "\x00"; # lines separated by NUL byte
		while (my $ln = <MODLINK>) {
			chomp($ln); # take NUL back off
			last if $ln eq '>>>EOF'; # deadlock prevention, win32 gets stuck on next read
			if ($buf) {
				$new_mods{$buf} = $ln;
				$buf = undef;
			} else {
				$buf = $ln;
			}
		}
		die "Odd number of lines from module's \%INC" if defined $buf;
		close MODLINK;
		waitpid($pid, 0);

	} else {
		# child: write to parent via STDOUT
		unshift(@INC, $dir);
		local $\ = "\x00"; # separate lines with NUL byte
		eval <<EVAL;
require $mod_single->[0];
while (my \@i = each \%INC) {
	print for \@i;
}
EVAL
		print ">>>EOF"; # deadlock prevention
		# don't close STDOUT...
		exit 0;
	}

	# it has to have loaded itself, if nothing else
	my @new_paths = keys %new_mods;
	die "Broken module: $mod_single->[0]" unless scalar(@new_paths) >= scalar(keys %old_mods);

	my @mods = ();
	for my $relpath (@new_paths) {
		next if exists $old_mods{$relpath};     # not loaded after fork()
		next unless -f catfile($dir, $relpath); # not a bundled module

		my ($vol, $dir_text, $file) = splitpath($relpath);
		my (@dirs) = $dir_text ? splitdir($dir_text) : ();
		pop(@dirs) unless $dirs[$#dirs];
		$file =~ s/\.pm$//;
		my $final = join('::', @dirs, $file);
		next if $final eq $mod_single->[0];     # skip the exact module itself
		push(@mods, $final);
	}

	return [ @mods ];
}

sub resolve_load { # state module_info dependency_names -> void
	my ($st, $mod_single) = @_;
	my ($loaded, $deferred, $order) = @{$st}{qw( loaded deferred order )};

	# defer loading if any dependencies are not loaded
	for (@{$mod_single->[2]}) {
		if (! $loaded->{$_}) {
			exists($deferred->{$_}) ? push(@{$deferred->{$_}}, $mod_single) : ($deferred->{$_} = [ $mod_single ]);
			return;
		}
	}

	# all dependencies present, load this module
	push(@$order, $mod_single);
	$loaded->{$mod_single->[0]} = 1;

	# re-check loading of all modules that depended on this one
	if (my $defer_list = $deferred->{$mod_single->[0]}) {
		delete $deferred->{$mod_single->[0]}; # hide this info we're already handling
		for my $dep_mod_single (@$defer_list) {
			resolve_load($st, $dep_mod_single);
		}
	}
}

