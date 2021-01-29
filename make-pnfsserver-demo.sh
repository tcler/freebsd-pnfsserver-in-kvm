#!/bin/bash

#dependency check: kiss-vm-ns
#-------------------------------------------------------------------------------
if ! which vm; then
	KissVMUrl=https://github.com/tcler/kiss-vm-ns
	cat <<-EOF >&2
	{WARN} please install kiss-vm at first by run:
	 sudo bash -c "git clone --depth=1 "$KissVMUrl" && make -C kiss-vm-ns && vm --prepare"
	EOF

	exit 1
fi

Cleanup() {
	rm -f $stdlogf
	exit
}
trap Cleanup EXIT #SIGINT SIGQUIT SIGTERM

#create freebsd VMs
#-------------------------------------------------------------------------------
freebsd_nvr="FreeBSD-12.2"
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

echo "{INFO} remove existed VMs ..." >&2
vm del freebsd-pnfs-ds1 freebsd-pnfs-ds2 freebsd-pnfs-mds freebsd-pnfs-client

echo "{INFO} creating VMs ..." >&2
tmux new -d "/usr/bin/vm $freebsd_nvr -n $vm_ds1 -i $imagef -f"
tmux new -d "/usr/bin/vm $freebsd_nvr -n $vm_ds2 -i $imagef -f"
tmux new -d "/usr/bin/vm $freebsd_nvr -n $vm_mds -i $imagef -f"
tmux new -d "/usr/bin/vm $freebsd_nvr -n $vm_client -i $imagef -f"

port_available() { nc $1 $2 </dev/null &>/dev/null; }

#config freebsd pnfs ds server
for dsserver in $vm_ds1 $vm_ds2; do
	until port_available ${dsserver} 22; do sleep 2; done
	vm cpto ${dsserver} pnfs-ds.sh .
	vm exec -v ${dsserver} sh pnfs-ds.sh
	vm exec -v ${dsserver} -- showmount -e localhost
done

#config freebsd pnfs mds server
ds1addr=$(vm if $vm_ds1)
ds2addr=$(vm if $vm_ds2)
expdir=/export
until port_available ${vm_mds} 22; do sleep 2; done
vm cpto ${vm_mds} pnfs-mds.sh .
vm exec -v ${vm_mds} sh pnfs-mds.sh $ds1addr $ds2addr $expdir
vm exec -v ${vm_mds} -- mount -t nfs
vm exec -v ${vm_mds} -- showmount -e localhost

#config freebsd pnfs client
until port_available ${vm_client} 22; do sleep 2; done
vm cpto ${vm_client} pnfs-client.sh .
vm exec -v ${vm_client} sh pnfs-client.sh

#mount test from freebsd client
nfsmp=/mnt/nfsmp
mdsaddr=$(vm if $vm_mds)
vm exec -v ${vm_client} -- mkdir -p $nfsmp
vm exec -v ${vm_client} -- mount -t nfs -o nfsv4,minorversion=1,pnfs $mdsaddr:/ $nfsmp
vm exec -v ${vm_client} -- mount -t nfs
vm exec -v ${vm_client} -- sh -c "'echo 0123456789abcdef >$nfsmp/testfile'"
vm exec -v ${vm_client} -- ls -l $nfsmp/testfile
vm exec -v ${vm_client} -- cat $nfsmp/testfile

vm exec -v ${vm_mds} -- ls -l $expdir/testfile
vm exec -v ${vm_mds} -- cat $expdir/testfile
vm exec -v ${vm_mds} -- pnfsdsfile $expdir/testfile

#mount test from linux host
if [[ $(id -u) = 0 ]]; then
	mkdir -p $nfsmp
	mount -t nfs -o nfsvers=4.1 freebsd-pnfs-mds:/ $nfsmp
	echo "hello pnfs" >$nfsmp/hello-pnfs.txt
	ls -l $nfsmp/hello-pnfs.txt
	cat $nfsmp/hello-pnfs.txt
else
	cat <<-EOF

		#---------------------------------------------------------------
		# you can do test from linux like:
		sudo mkdir -p $nfsmp
		sudo mount -t nfs -o nfsvers=4.1 $mdsaddr:/ $nfsmp
		sudo tee $nfsmp/hello-pnfs.txt <<<"hello pnfs"
		ls -l $nfsmp/hello-pnfs.txt
		cat $nfsmp/hello-pnfs.txt
		#---------------------------------------------------------------
	EOF
fi
