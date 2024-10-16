#!/bin/bash

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

timeServer=clock.corp.redhat.com
host $timeServer|grep -q not.found: && timeServer=2.fedora.pool.ntp.org
TIME_SERVER=$timeServer
downhostname=download.devel.redhat.com
LOOKASIDE_BASE_URL=${LOOKASIDE:-http://${downhostname}/qa/rhts/lookaside}

#-------------------------------------------------------------------------------
#kiss-vm should have been installed and initialized
vm prepare >/dev/null

Cleanup() {
	rm -f $stdlogf
	exit
}
trap Cleanup EXIT #SIGINT SIGQUIT SIGTERM

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}

#create freebsd VMs
#-------------------------------------------------------------------------------
freebsd_nvr="FreeBSD-12.4"
nfs4minver=1
freebsd_nvr="FreeBSD-14.1"
nfs4minver=2
vm_ds1=freebsd-pnfs-ds1
vm_ds2=freebsd-pnfs-ds2
vm_mds=freebsd-pnfs-mds
vm_fbclient=freebsd-pnfs-client

vm_rhel=${vm_rhel:-fbpnfs-rhel-client}
pkgs=nfs-utils,expect,iproute-tc,kernel-modules-extra,vim,bind-utils,tcpdump

stdlogf=/tmp/std-$$.log
vm create --downloadonly $freebsd_nvr 2>&1 | tee $stdlogf
imagef=$(sed -n '${s/^.* //; p}' $stdlogf)
if [[ ! -f "$imagef" ]]; then
	echo "{WARN} seems cloud image file download fail." >&2
	exit 1
fi
if [[ $imagef = *.xz ]]; then
	echo "{INFO} decompress $imagef ..."
	xz -d $imagef
	imagef=${imagef%.xz}
	if [[ ! -f ${imagef} ]]; then
		echo "{WARN} there is no $imagef, something was wrong." >&2
		exit 1
	fi
fi

echo -e "\n{INFO} remove existed VMs ..."
vm del freebsd-pnfs-ds1 freebsd-pnfs-ds2 freebsd-pnfs-mds freebsd-pnfs-client

echo -e "\n{INFO} creating VMs ..."
trun -tmux /usr/bin/vm create $distro -n $vm_rhel -p $pkgs --nointeract --saveimage -f "${@}"
trun -tmux /usr/bin/vm create $freebsd_nvr -n $vm_ds1 -dsize 80 -i $imagef -f
trun -tmux /usr/bin/vm create $freebsd_nvr -n $vm_ds2 -dsize 80 -i $imagef -f
trun -tmux /usr/bin/vm create $freebsd_nvr -n $vm_mds -dsize 40 -i $imagef -f
trun       /usr/bin/vm create $freebsd_nvr -n $vm_fbclient -i $imagef -f --nointeract

port_available() { nc $1 $2 </dev/null &>/dev/null; }
echo -e "\n{INFO} waiting VMs install finish ..."

#config freebsd pnfs ds server
for dsserver in $vm_ds1 $vm_ds2; do
	until port_available ${dsserver} 22; do sleep 2; done
	echo -e "\n{INFO} setup ${dsserver}:"
	vm cpto ${dsserver} freebsd-pnfs-ds.sh .
	vm exec -v ${dsserver} sh freebsd-pnfs-ds.sh
	vm exec -v ${dsserver} -- showmount -e localhost
done

#config freebsd pnfs mds server
echo -e "\n{INFO} setup ${vm_mds}:"
ds1addr=$(vm ifaddr $vm_ds1)
ds2addr=$(vm ifaddr $vm_ds2)
until port_available ${vm_mds} 22; do sleep 2; done
vm cpto ${vm_mds} freebsd-pnfs-mds.sh .
vm exec -v ${vm_mds} sh freebsd-pnfs-mds.sh $ds1addr $ds2addr
vm exec -v ${vm_mds} -- mount -t nfs
vm exec -v ${vm_mds} -- showmount -e localhost

#config freebsd pnfs client
echo -e "\n{INFO} setup ${vm_fbclient}:"
until port_available ${vm_fbclient} 22; do sleep 2; done
vm cpto ${vm_fbclient} freebsd-pnfs-client.sh .
vm exec -v ${vm_fbclient} sh freebsd-pnfs-client.sh

#mount test from freebsd client
expdir0=/export0
expdir1=/export1
echo -e "\n{INFO} test from ${vm_fbclient}:"
nfsmp=/mnt/nfsmp
nfsmp2=/mnt/nfsmp2
mdsaddr=$(vm ifaddr $vm_mds)
vm exec -v ${vm_fbclient} -- mkdir -p $nfsmp $nfsmp2
vm exec -v ${vm_fbclient} -- mount -t nfs -o nfsv4,minorversion=$nfs4minver,pnfs $mdsaddr:$expdir0 $nfsmp
vm exec -v ${vm_fbclient} -- mount -t nfs -o nfsv4,minorversion=$nfs4minver,pnfs $mdsaddr:$expdir1 $nfsmp2
vm exec -v ${vm_fbclient} -- mount -t nfs
vm exec -v ${vm_fbclient} -- sh -c "echo 0123456789abcdef >$nfsmp/testfile"
vm exec -v ${vm_fbclient} -- sh -c "echo 0123456789abcdef >$nfsmp2/testfile"

vm exec -v ${vm_fbclient} -- ls -l $nfsmp/testfile
vm exec -v ${vm_fbclient} -- cat $nfsmp/testfile

vm exec -v ${vm_fbclient} -- ls -l $nfsmp2/testfile
vm exec -v ${vm_fbclient} -- cat $nfsmp2/testfile

vm exec -v ${vm_mds} -- ls -l $expdir0/testfile
vm exec -v ${vm_mds} -- cat $expdir0/testfile
vm exec -v ${vm_mds} -- pnfsdsfile $expdir0/testfile

vm exec -v ${vm_mds} -- ls -l $expdir1/testfile
vm exec -v ${vm_mds} -- cat $expdir1/testfile
vm exec -v ${vm_mds} -- pnfsdsfile $expdir1/testfile

#mount test from linux Guest
nfsver=4.1
nfsver=4.2
until port_available ${vm_rhel} 22; do sleep 2; done
echo -e "\n{INFO} test from ${vm_rhel}:"
vm exec -vx $vm_rhel -- showmount -e $mdsaddr
vm exec -vx $vm_rhel -- mkdir -p $nfsmp
vm exec -vx $vm_rhel -- mount -t nfs -o nfsvers=$nfsver $mdsaddr:$expdir0 $nfsmp
vm exec -vx $vm_rhel -- mount -t nfs4
vm exec -vx $vm_rhel -- bash -c "echo 'hello pnfs' >$nfsmp/hello-pnfs.txt"
vm exec -vx $vm_rhel -- ls -l $nfsmp
vm exec -vx $vm_rhel -- cat $nfsmp/hello-pnfs.txt
vm exec -vx $vm_rhel -- cat $nfsmp/testfile
vm exec -vx $vm_rhel -- umount $nfsmp
