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

	App::FedoraPack::cli::main();
}

