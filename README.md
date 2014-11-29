# Synopsis

**fedora-pack** integrates the
[Fedora Cloud image](https://fedoraproject.org/en/get-fedora#clouds)
with [Packer](http://www.packer.io/).

fedora-pack currently consists of two parts:

1. **fedora2ova** which converts the _raw_ disk image to an OVA for Packer.
2. **make-provisioner** which creates a shell provisioner from a tree of
	 files.

## A Word of Caution

I abandoned using Fedora Cloud as it would frequently corrupt its disk on
shutdown of a local VM.  I don’t exercise `fedora2ova` nor the Fedora system
code in `make-provisioner` myself anymore.


# fedora2ova example

    ./bin/fedora2ova -k ~/.ssh/aws.pub -n f20 Fedora-x86_64-20.raw.xz

This takes all the steps needed to build a VM whose name starts with `f20`
and whose main user (`fedora`, in this case) is accessible with the given SSH
key.  The VM will be exported to the current directory as `f20.ova` for use
with Packer's VirtualBox builder.

You can also specify the temp dir, used for intermediate files, with `-t DIR`
and the output directory with `-o DIR`.  Without `-t`, a temporary directory
is created and destroyed automatically; the tmpdir is preserved when `-t` is
used.

`fedora2ova` assumes it is using the 64-bit image by default; you may instead
create a 32-bit guest by adding the `--32bit` flag.

More options may be available.  Check `fedora2ova --help` or `perldoc
fedora2ova` for more details.


# make-provisioner example

    ./bin/make-provisioner --system-ubuntu=trusty --exec=install.pl ~/make_server

This creates a self-extracting provisioner containing all regular files and
symlinks within `make_server`.  When this provisioner is run on the guest by
packer, it will install Perl, unpack the `make_server` tree, and run
`make_server/install.pl` using the system Perl it installed.

The provisioner is written to standard output by default, which can be changed
with the `--save-as=` option.

**make-provisioner** tries to be helpful, and will install some basic
dependency management along with the language itself.  When `--perl` is
included, this means that the full core Perl is installed, along with `cpanm`,
`local::lib`, and even `carton`.  Likewise, `--php` will install not only
php-cli, but `/usr/bin/composer.phar`; and python 2 and 3 each include pip and
virtualenv.  (The latter will be named according to the platform convention;
`make-provisioner` does not try to establish its own standard.)

As of 0.7.0, multiple bundle directories and scripts to execute are permitted.
Directory basenames may not collide, nor begin with `_`; in event of collision
of script names, the first one found will be invoked (effectively shadowing
the rest).


# Dependencies

## Fedora Cloud disk image

The xz-compressed (or uncompressed) disk image from the
[Fedora Cloud page](https://fedoraproject.org/en/get-fedora#clouds).
fedora2ova will automatically decompress it and leave it in its decompressed
form.

## Perl 5.10.0 or newer

The host (the machine running fedora-pack) needs Perl 5.10.0 or newer.  It
does expect a complete core installation of Perl (install `perl-core` on
Fedora) but it relies on absolutely nothing from the CPAN.  And it’s proud of
it.

0.7.0 is mainly tested on Strawberry Perl 5.10.0-6 portable.

## Disk Space

At least a gigabyte free is recommended for using `fedora2ova`.  The process
will create multiple disk images:

* An uncompressed raw image from Fedora.
* An uncompressed VDI image attached to the VM.
* A compressed copy in the exported OVA.

When the OVA is further customized by Packer, another VDI and OVA are created.

## SSH key pair

You will need to supply a public key, which will be authorized for the
instance.

## VirtualBox

The OVA is built using the VirtualBox command line interface.

## xorriso (available in Homebrew)

Used for creating the user-data and meta-data to enable login to the Fedora
Cloud image.

## xz | pxz | pixz (all available in Homebrew)

The Fedora Cloud raw disk image is currently compressed with `xz`, which OS X
needs a little help to decompress.  These commands will be run automatically
by fedora-pack only when needed.

On a reasonably modern Linux host, xz was probably installed by default.
