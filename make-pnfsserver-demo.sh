#!/bin/bash

#dependency check: kiss-vm-ns
#-------------------------------------------------------------------------------
if ! which vm; then
	KissVMUrl=https://github.com/tcler/kiss-vm-ns
	echo -e "{INFO} installing kiss-vm ..."
	while true; do
		git clone --depth=1 "$KissVMUrl" && make -C kiss-vm-ns
		which vm && break
		sleep 5
		echo -e "{warn} installing kiss-vm  fail, try again ..."
	done
	vm prepare >/dev/null
fi

Cleanup() {
	rm -f $stdlogf
	exit
}
trap Cleanup EXIT #SIGINT SIGQUIT SIGTERM

run() {
	[[ $# -eq 0 ]] && return 0
	echo "[run]" "$@"
	"$@"
}
get_if_addr() {
	local _vm=$1
	local _pub=$2
	if [[ -z "$pub" ]]; then
		vm if $_vm
	else
		vm exec $_vm -- ifconfig vtnet1 | awk '$1=="inet" {print $2}'
	fi
}

pub=$1
if [[ -n "$pub" ]]; then
	echo -e "{INFO} creating macvlan if mv-host-pub ..."
	sudo netns host,mv-host-pub,dhcp
fi

#create freebsd VMs
#-------------------------------------------------------------------------------
freebsd_nvr="FreeBSD-12.2"
nfs4minver=1
freebsd_nvr="FreeBSD-13.0"
nfs4minver=2
vm_ds1=freebsd-pnfs-ds1
vm_ds2=freebsd-pnfs-ds2
vm_mds=freebsd-pnfs-mds
vm_client=freebsd-pnfs-client

stdlogf=/tmp/std-$$.log
vm --downloadonly $freebsd_nvr 2>&1 | tee $stdlogf
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
tmux new -d "/usr/bin/vm create $freebsd_nvr -n $vm_ds1 -dsize 80 -i $imagef -f"
tmux new -d "/usr/bin/vm create $freebsd_nvr -n $vm_ds2 -dsize 80 -i $imagef -f"
tmux new -d "/usr/bin/vm create $freebsd_nvr -n $vm_mds -dsize 40 -i $imagef -f"
tmux new -d "/usr/bin/vm create $freebsd_nvr -n $vm_client -i $imagef -f"

port_available() { nc $1 $2 </dev/null &>/dev/null; }
echo -e "\n{INFO} waiting VMs install finish ..."

#config freebsd pnfs ds server
for dsserver in $vm_ds1 $vm_ds2; do
	until port_available ${dsserver} 22; do sleep 2; done
	echo -e "\n{INFO} setup ${dsserver}:"
	vm cpto ${dsserver} pnfs-ds.sh .
	vm exec -v ${dsserver} sh pnfs-ds.sh
	vm exec -v ${dsserver} -- showmount -e localhost
done

#config freebsd pnfs mds server
echo -e "\n{INFO} setup ${vm_mds}:"
ds1addr=$(get_if_addr $vm_ds1 $pub)
ds2addr=$(get_if_addr $vm_ds2 $pub)
until port_available ${vm_mds} 22; do sleep 2; done
vm cpto ${vm_mds} pnfs-mds.sh .
vm exec -v ${vm_mds} sh pnfs-mds.sh $ds1addr $ds2addr
vm exec -v ${vm_mds} -- mount -t nfs
vm exec -v ${vm_mds} -- showmount -e localhost

#config freebsd pnfs client
echo -e "\n{INFO} setup ${vm_client}:"
until port_available ${vm_client} 22; do sleep 2; done
vm cpto ${vm_client} pnfs-client.sh .
vm exec -v ${vm_client} sh pnfs-client.sh

#mount test from freebsd client
expdir0=/export0
expdir1=/export1
echo -e "\n{INFO} test from ${vm_client}:"
nfsmp=/mnt/nfsmp
nfsmp2=/mnt/nfsmp2
mdsaddr=$(get_if_addr $vm_mds $pub)
vm exec -v ${vm_client} -- mkdir -p $nfsmp $nfsmp2
vm exec -v ${vm_client} -- mount -t nfs -o nfsv4,minorversion=$nfs4minver,pnfs $mdsaddr:$expdir0 $nfsmp
vm exec -v ${vm_client} -- mount -t nfs -o nfsv4,minorversion=$nfs4minver,pnfs $mdsaddr:$expdir1 $nfsmp2
vm exec -v ${vm_client} -- mount -t nfs
vm exec -v ${vm_client} -- sh -c "'echo 0123456789abcdef >$nfsmp/testfile'"
vm exec -v ${vm_client} -- sh -c "'echo 0123456789abcdef >$nfsmp2/testfile'"

vm exec -v ${vm_client} -- ls -l $nfsmp/testfile
vm exec -v ${vm_client} -- cat $nfsmp/testfile

vm exec -v ${vm_client} -- ls -l $nfsmp2/testfile
vm exec -v ${vm_client} -- cat $nfsmp2/testfile

vm exec -v ${vm_mds} -- ls -l $expdir0/testfile
vm exec -v ${vm_mds} -- cat $expdir0/testfile
vm exec -v ${vm_mds} -- pnfsdsfile $expdir0/testfile

vm exec -v ${vm_mds} -- ls -l $expdir1/testfile
vm exec -v ${vm_mds} -- cat $expdir1/testfile
vm exec -v ${vm_mds} -- pnfsdsfile $expdir1/testfile

#mount test from linux host
nfsver=4.1
nfsver=4.2
if [[ $(id -u) = 0 ]]; then
	cat <<-EOF

	{INFO} test from linux host
	EOF
	run mkdir -p $nfsmp
	run mount -t nfs -o nfsvers=$nfsver $mdsaddr:$expdir0 $nfsmp
	run mount -t nfs4
	run bash -c "echo 'hello pnfs' >$nfsmp/hello-pnfs.txt"
	run ls -l $nfsmp/hello-pnfs.txt
	run cat $nfsmp/hello-pnfs.txt
	run umount $nfsmp
else
	cat <<-EOF

	#---------------------------------------------------------------
	# you can do test from linux like:
	sudo mkdir -p $nfsmp
	sudo mount -t nfs -o nfsvers=$nfsver $mdsaddr:$expdir0 $nfsmp
	mount -t nfs4
	sudo bash -c "echo 'hello pnfs' >$nfsmp/hello-pnfs.txt"
	ls -l $nfsmp/hello-pnfs.txt
	cat $nfsmp/hello-pnfs.txt
	umount $nfsmp
	#---------------------------------------------------------------
	EOF
fi
echo
