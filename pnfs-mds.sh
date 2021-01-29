#!/bin/sh

ds_server0=$1
ds_server1=$2
expdir=${3:-/export}

if [ -z "$ds_server0" ] || [ -z "$ds_server1" ]; then
	echo "Usage: $0 <ds0> <ds2>"
	exit 1
fi

mntds0=/data0
mntds1=/data1

expdir0=/export0
expdir1=/export1

mkdir -p -m 700 $mntds0 $mntds1
mkdir -p $expdir $expdir0 $expdir1

cat <<EOF >>/etc/fstab
$ds_server0:/  $mntds0 nfs rw,vers=4,minorversion=1,soft,retrans=2 0 0
$ds_server1:/  $mntds1 nfs rw,vers=4,minorversion=1,soft,retrans=2 0 0
EOF
mount -vvv $mntds0 || exit 1
mount -vvv $mntds1 || exit 1

cat <<EOF >/etc/exports
$expdir -maproot=root -sec=sys
V4: $expdir -sec=sys
EOF

echo 'vfs.nfsd.default_flexfile=1' >>/etc/sysctl.conf

#enable nfs server
egrep -i ^nfs_server_enable=.?YES /etc/rc.conf ||
cat <<EOF >>/etc/rc.conf
rpcbind_enable="YES"
mountd_enable="YES"
nfs_server_enable="YES"
nfsv4_server_enable="YES"
nfsuserd_enable="YES"

nfs_server_flags="-u -t -n 32 -m 2 -p $ds_server0:$mntds0,$ds_server1:$mntds1"
mountd_flags="-S"
nfsuserd_flags="-manage-gids"
EOF
service nfsd start
service mountd restart
service nfsuserd start
sysctl vfs.nfsd.default_flexfile=1

#enable nfs client
egrep -i ^nfs_client_enable=.?YES /etc/rc.conf ||
echo 'nfs_client_enable="YES"' >>/etc/rc.conf
service nfsclient start
