# freebsd-pnfsserver-in-kvm
Here we provide a script to automatically create a freebsd pnfs-server VMs cluster

# platform requires
In order to run this script correctly, you need a PC or laptop with 16G RAM, and the OS shoud be CentOS-7/RHEL-7/Fedora-30 or higher

# software requires
You also need to install tmux and [kiss-vm-ns](https://github.com/tcler/kiss-vm-ns) in advance:
```
sudo yum install -y tmux
git clone https://github.com/tcler/kiss-vm-ns && sudo make -C kiss-vm-ns && sudo vm --prepare"
```

# quick start
```
git clone https://github.com/tcler/freebsd-pnfsserver-in-kvm
cd freebsd-pnfsserver-in-kvm
./make-pnfsserver-demo.sh

vm ls
vm login freebsd-pnfs-mds     #and do more tests and observations
vm login freebsd-pnfs-client  #and do more tests and observations
```

# ref
https://www.freebsd.org/cgi/man.cgi?query=pnfsserver  
https://people.freebsd.org/~rmacklem/pnfs-planb-setup.txt  
