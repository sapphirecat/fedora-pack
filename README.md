# Synopsis

The [Fedora Cloud image](https://fedoraproject.org/en/get-fedora#clouds)
isn't [Packer](http://www.packer.io/)-ready out of the
box.  fedora-pack takes care of turning that compressed, raw disk image into a
full-fleged OVA export.


# Example Usage

    ./bin/fedora2ova -k ~/.ssh/aws.pub -n f20 Fedora-x86_64-20.raw.xz

This takes all the steps needed to build a VM whose name starts with `f20`
and whose main user (`fedora`, in this case) is accessible with the given SSH
key.  The VM will be exported to your system’s temporary directory—typically
/tmp—as `f20.ova` for use with Packer's VirtualBox builder.

You can also specify the temp dir, used for intermediate files, with `-t DIR`
and the output directory with `-o DIR`.  Without `-t`, a temporary directory
is created and destroyed automatically; the tmpdir is preserved when `-t` is
used.

`fedora2ova` assumes it is using the 64-bit image by default; you may instead
create a 32-bit guest by adding the `--32bit` flag.

More options may be available.  Check `fedora2ova --help` or `perldoc
fedora2ova` for more details.


# Dependencies

## Disk Space

At least a gigabyte free is recommended.  The process will create multiple
disk images:

* An uncompressed raw image directly from Fedora.
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
