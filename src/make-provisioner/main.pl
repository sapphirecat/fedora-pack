#!/usr/bin/env perl

# https://github.com/sapphirecat/fedora-pack
#
# Self-extracting Packer shell provisioners for Linux
# Copyright (C) 2014 Sapphire Cat <https://github.com/sapphirecat>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use 5.010;
use mro 'c3';
use strict;
use warnings;

eval 'use IO::File (); use IO::Handle ();' if $] < 5.014;
use FindBin ();

#INSERT_PACKAGES#

{
	package main;

	BEGIN {
		if (! exists($INC{'App/FedoraPack/cli.pm'})) {
			# TODO: recursively enumerate *.pm modules in BFS under $FB::Bin and use
			# them all, instead of hardcoding the leaves
			eval <<EVAL;
			use lib \$FindBin::Bin;
			use App::FedoraPack::cli;
			use App::FedoraPack::System::Ubuntu;
			use App::FedoraPack::System::AmazonLinux;
EVAL
		}
	}

	App::FedoraPack::cli->main(\@ARGV);
}

__END__

=head1 NAME

make-provisioner - create Packer shell provisioners for Linux guests

=head1 SYNOPSIS

	# the minimal command
	make-provisioner --system-ubuntu=utopic --exec=main.sh ../bundle
	
	# include some other languages, specify exec language explicitly;
	# this will invoke bundle/provision.py in the guest
	make-provisioner --system-fedora=20 --python3 --perl --php \
		--exec=python3,provision.py ../bundle

=head1 DESCRIPTION

B<make-provisioner> builds a Packer shell provisioner based on some files in
the host filesystem, for use with a supported Linux guest.

The source tree must contain at least one driver script (defined by the
I<--exec> option), and optionally, a collection of other files that the driver
needs to do its job.

All these are packed together into a gzip-compressed tar archive as the
payload of a self-extracting bash script.  Upon being used as a provisioner,
the tarball is extracted again, and the driver script launched inside the
guest system.

By the time the provisioner is run, any known features (such as languages,
extra repos, or similar) defined by the guest packages and requested as
options during the run of B<make-provisioner> are already added.

=head1 SUPPORTED GUESTS

=over 4

=item Debian: 7.x (wheezy) - 8.x (jessie)

Chosen using I<--system-debian=8> style, or I<--system-debian=jessie>.

=item Ubuntu: 14.04 LTS (Trusty Tahr) - 14.10 (Utopic Unicorn)

Chosen using I<--system-ubuntu=14.04> style, or I<--system-ubuntu=trusty>.

=item Fedora: 20 - 21

Chosen using I<--system-fedora=21> style.

=item Amazon Linux: 2014.09

The Amazon Linux AMI.  As this distribution has a rolling release, only the
latest version at the time of fedora-pack's release is supported.  The version
is, however, still required.

Chosen using I<--system-amazon=2014.09>, or without using the version, as
I<--system-amazon>.  However, the latter style will not produce an error if
fedora-pack does not support the desired/current Amazon Linux release.

Local option: I<--epel> will enable the EPEL repo for packages.  By default,
only the base repo is enabled.

=back

=head1 SUPPORTED FEATURES

The base B<fedora-pack> system supports the following features to pre-install.
All features currently described here take an optional version as well, to
require a minimum version of the language.  E.g. C<--perl 5.16> will fail on
Debian Wheezy, which only provides 5.14, while it will succeed on Ubuntu
Utopic, which provides 5.20.

=over 4

=item bash

The Bourne-Again Shell.  This is already installed on all supported guests,
but provided for completeness.  It is automatically included (and invoked on)
C<--exec> scripts ending in I<.sh>.

=item perl

The Perl 5 language, with I<cpanm>, I<carton>, and I<local::lib> also
installed.  It is invoked for scripts ending in I<.pl>.

=item php

The PHP language, with I<composer> installed as C</usr/bin/composer>.  It is
invoked for scripts ending in I<.php>.

=item python2 and python3

The 2.x and 3.x versions of the Python language, respectively.  The current
version of fedora-pack B<only> installs the vanilla Python package, with no
additions (notably, older versions used to install pip and virtualenv.)

Scripts ending in I<.py> are ambiguous; while they are currently invoked with
Python 2, B<this may change in the future.>  It is safest to invoke them using
an specified language, as in C<--exec=python3,path/to/script.py>.

=back

=head1 SEE ALSO

L<http://packer.io/>, L<http://docker.io>

(This has little to do with Docker, but you may find it suits your needs
better than Packer.)

=cut

