# freebsd-pnfsserver-in-kvm
Here we provide a script to automatically create a freebsd pnfs-server VMs cluster

# platform requires
In order to run this script correctly, you need a PC or laptop with 16G RAM, and the OS shoud be CentOS/RHEL-7,Fedora-30 or higher.
[Update] Now(October 2024) recommand RHEL/Rocky/AlmaLinux-9,Fedora-40 or higher

# software requires
You also need to install tmux and [kiss-vm-ns](https://github.com/tcler/kiss-vm-ns) in advance:
```
sudo yum install -y tmux
git clone https://github.com/tcler/kiss-vm-ns && sudo make -C kiss-vm-ns && sudo vm prepare
```

# quick start
```
git clone https://github.com/tcler/freebsd-pnfsserver-in-kvm
cd freebsd-pnfsserver-in-kvm
time ./make-freebsd-pnfsserver.sh [8|9|10|kiss-vm distro name] [vm-create options]
                                  #^^^^^^ here 8,9,10 means rhel/centos-stream 8,9,10

vm ls
vm login freebsd-pnfs-mds     #login freebsd pnfs-mds server and do more tests/observations
vm login freebsd-pnfs-client  #login freebsd client and do more tests/observations
vm login fbpnfs-linux-client  #login linux client and do more tests/observations
```

# ref
https://www.freebsd.org/cgi/man.cgi?query=pnfsserver  
https://people.freebsd.org/~rmacklem/pnfs-planb-setup.txt  
