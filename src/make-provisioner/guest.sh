#!/bin/bash
[ -z $FEDORAPACK_DEBUG ] || set -x
set -e

# find ourselves
self_file="$0"
[ -e "$self_file" ] || self_file="$(which "$self_file")"
cut_line=$(( `grep -an '^#END_STAGE1$' "$self_file" | cut -d: -f1` + 1 ))
if [ "$cut_line" -le 1 ] ; then
	echo "Cannot find '#END_STAGE1' line - extraction failed" >&2
	exit 1
fi

# make absolute
[ "$(echo "$self_file" | cut -c1)" == / ] || \
	self_file="$(pwd -P)/$self_file"

# exec payloads in workdir
sudo install -d -m 0700 -o `id -un` -g `id -gn` /var/local/fedora-pack
cd /var/local/fedora-pack
sudo yum -q -y install @PACKAGES@
@POST_SH@

tail -n +$cut_line "$self_file" | tar zxf -
cd @TAR_TOPDIR@
exec @RUNNER@ `pwd`

# Magic token so that we don't hardcode any line-numbers.
#END_STAGE1
