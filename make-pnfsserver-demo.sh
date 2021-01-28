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
	rm -f $imagef
	imagef=${imagef%.xz}
	if [[ ! -f ${imagef} ]]; then
		echo "{WARN} there is no $imagef, something was wrong." >&2
		exit 1
	fi
fi

echo "{INFO} remove existed VMs ..." >&2
vm del freebsd-pnfs-ds1 freebsd-pnfs-ds2 freebsd-pnfs-mds freebsd-pnfs-client

echo "{INFO} creating VMs ..." >&2
tmux new -d "/usr/bin/vm $freebsd_nvr -n freebsd-pnfs-ds1 -i $imagef -f"
tmux new -d "/usr/bin/vm $freebsd_nvr -n freebsd-pnfs-ds2 -i $imagef -f"
tmux new -d "/usr/bin/vm $freebsd_nvr -n freebsd-pnfs-mds -i $imagef -f"
#tmux new -d "/usr/bin/vm $freebsd_nvr -n freebsd-pnfs-client -i $imagef -f"

port_available() { nc $1 $2 </dev/null &>/dev/null; }

#config freebsd pnfs ds server
for dsserver in freebsd-pnfs-ds1 freebsd-pnfs-ds2; do
	until port_available ${dsserver} 22; do sleep 2; done
	vm cpto ${dsserver} pnfs-ds.sh .
	vm exec -v ${dsserver} sh pnfs-ds.sh
	vm exec -v ${dsserver} -- showmount -e localhost
done

#config freebsd pnfs mds server
mdsserver=freebsd-pnfs-mds
ds1addr=$(vm if freebsd-pnfs-ds1)
ds2addr=$(vm if freebsd-pnfs-ds2)
until port_available ${mdsserver} 22; do sleep 2; done
vm cpto ${mdsserver} pnfs-mds.sh .
vm exec -v ${mdsserver} sh pnfs-mds.sh $ds1addr $ds2addr
vm exec -v ${mdsserver} -- mount -t nfs
vm exec -v ${mdsserver} -- showmount -e localhost

#config freebsd pnfs client
