#!/bin/bash

##########################################################
# spawn_local_vms.sh
# author: erhudy
#
# This script will spawn a set of VirtualBox VMs that can be managed with
# Ansible. This script only sets up the VMs; installing the OS on the
# bootstrap node and running the Ansible playbooks against the VMs is up to
# the user. (If you want to be able to spawn a Cloud Compute cluster
# in an entirely automated fashion, you will need to use Vagrant.)
##########################################################

set -e

for CMD in VBoxManage git pcregrep; do
  if ! which $CMD >/dev/null; then
    echo "Could not find $CMD on PATH, exiting." >&2
    exit 1
  fi
done

# locate repo root
REPO_ROOT=$(git rev-parse --show-toplevel)

# load bootstrap configurations
source $REPO_ROOT/bootstrap/config/bootstrap_config.sh.defaults
CONFIG_OVERRIDES=$REPO_ROOT/bootstrap/config/bootstrap_config.sh.overrides

if [[ -f $CONFIG_OVERRIDES ]]; then
  source $CONFIG_OVERRIDES
fi

# destroy existing BCPC VMs
for VM in bcpc-bootstrap bcpc-vm1 bcpc-vm2 bcpc-vm3 bcpc-vm4 bcpc-vm5 bcpc-vm6; do
  if VBoxManage list vms | grep -q $VM; then
    VBoxManage controlvm $VM poweroff && true
    VBoxManage unregistervm $VM --delete
  fi
done

# destroy and recreate host-only networks
VBoxManage hostonlyif remove vboxnet0 && true
VBoxManage hostonlyif remove vboxnet1 && true
VBoxManage hostonlyif remove vboxnet2 && true

VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet0 --ip 10.0.100.2 --netmask 255.255.255.0

VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet1 --ip 172.16.100.2 --netmask 255.255.255.0

VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet2 --ip 192.168.100.2 --netmask 255.255.255.0

# if VirtualBox created DHCP servers, burn them and salt the earth
VBoxManage dhcpserver remove --ifname vboxnet0 && true
VBoxManage dhcpserver remove --ifname vboxnet1 && true
VBoxManage dhcpserver remove --ifname vboxnet2 && true

# Initialize VM lists
VMS="bcpc-vm1 bcpc-vm2 bcpc-vm3"
if [ $MONITORING_NODES -gt 0 ]; then
  i=1
  while [ $i -le $MONITORING_NODES ]; do
    MON_VM="bcpc-vm`expr 3 + $i`"
    VMS="$VMS $MON_VM"
    i=`expr $i + 1`
  done
fi

# get the location of the default machine folder
if [[ $(uname) == "Darwin" ]]; then
  SED="sed -E"
else
  SED="sed -r"
fi
DMF_SET=$(VBoxManage list systemproperties | grep '^Default machine folder:')
DMF_PATH=$(echo "$DMF_SET" | $SED 's/^Default machine folder:[[:space:]]+(.+)$/\1/')

# spawn and configure bootstrap VM
echo "Creating bootstrap VM"
VBoxManage createvm --name bcpc-bootstrap --register
VBoxManage modifyvm bcpc-bootstrap --ostype Ubuntu_64
VBoxManage modifyvm bcpc-bootstrap --memory $BOOTSTRAP_VM_MEM
VBoxManage modifyvm bcpc-bootstrap --cpus $BOOTSTRAP_VM_CPUS
VBoxManage modifyvm bcpc-bootstrap --nic1 nat
VBoxManage modifyvm bcpc-bootstrap --nictype1 82543GC
VBoxManage modifyvm bcpc-bootstrap --nic2 hostonly
VBoxManage modifyvm bcpc-bootstrap --nictype2 82543GC
VBoxManage modifyvm bcpc-bootstrap --hostonlyadapter2 vboxnet0
VBoxManage modifyvm bcpc-bootstrap --nic3 hostonly
VBoxManage modifyvm bcpc-bootstrap --nictype3 82543GC
VBoxManage modifyvm bcpc-bootstrap --hostonlyadapter3 vboxnet1
VBoxManage modifyvm bcpc-bootstrap --nic4 hostonly
VBoxManage modifyvm bcpc-bootstrap --nictype4 82543GC
VBoxManage modifyvm bcpc-bootstrap --hostonlyadapter4 vboxnet2
# configure storage devices for bootstrap VM
VBoxManage storagectl bcpc-bootstrap --name "SATA" --add sata --portcount 3 --hostiocache on
VBoxManage createhd --filename "$DMF_PATH/bcpc-bootstrap/bcpc-bootstrap-sda.vdi" --size $BOOTSTRAP_VM_DRIVE_SIZE
VBoxManage storageattach bcpc-bootstrap --storagectl "SATA" --device 0 --port 0 --type hdd --medium "$DMF_PATH/bcpc-bootstrap/bcpc-bootstrap-sda.vdi"
VBoxManage createhd --filename "$DMF_PATH/bcpc-bootstrap/bcpc-bootstrap-sdb.vdi" --size 8192
VBoxManage storageattach bcpc-bootstrap --storagectl "SATA" --device 0 --port 1 --type hdd --medium "$DMF_PATH/bcpc-bootstrap/bcpc-bootstrap-sdb.vdi"
VBoxManage createhd --filename "$DMF_PATH/bcpc-bootstrap/bcpc-bootstrap-sdc.vdi" --size 204800
VBoxManage storageattach bcpc-bootstrap --storagectl "SATA" --device 0 --port 2 --type hdd --medium "$DMF_PATH/bcpc-bootstrap/bcpc-bootstrap-sdc.vdi"
# configure DVD drive to boot from and set boot device to DVD drive (user must attach boot medium)
VBoxManage storagectl bcpc-bootstrap --name "IDE" --add ide
VBoxManage storageattach bcpc-bootstrap --storagectl "IDE" --device 0 --port 0 --type dvddrive --medium emptydrive
VBoxManage modifyvm bcpc-bootstrap --boot1 dvd

# spawn and configure cluster VMs
# note: NIC type 82543GC is required for PXE boot to work
for VM in $VMS; do
  echo "Creating cluster VM $VM"
  VBoxManage createvm --name $VM --register
  VBoxManage modifyvm $VM --ostype Ubuntu_64
  VBoxManage modifyvm $VM --memory $CLUSTER_VM_MEM
  VBoxManage modifyvm $VM --cpus $CLUSTER_VM_CPUS
  VBoxManage modifyvm $VM --nic1 hostonly
  VBoxManage modifyvm $VM --nictype1 82543GC
  VBoxManage modifyvm $VM --hostonlyadapter1 vboxnet0
  VBoxManage modifyvm $VM --nic2 hostonly
  VBoxManage modifyvm $VM --nictype2 82543GC
  VBoxManage modifyvm $VM --hostonlyadapter2 vboxnet1
  VBoxManage modifyvm $VM --nic3 hostonly
  VBoxManage modifyvm $VM --nictype3 82543GC
  VBoxManage modifyvm $VM --hostonlyadapter3 vboxnet2
  VBoxManage storagectl $VM --name "SATA" --add sata --portcount 5 --hostiocache on

  PORT=0
  for DISK in a b c d e; do
      VBoxManage createhd --filename "$DMF_PATH/$VM/$VM-sd$DISK.vdi" --size $CLUSTER_VM_DRIVE_SIZE
      VBoxManage storageattach $VM --storagectl "SATA" --device 0 --port $PORT --type hdd --medium "$DMF_PATH/$VM/$VM-sd$DISK.vdi"
      PORT=$((PORT+1))
  done

  # attach PXE boot ROM
  VBoxManage setextradata $VM VBoxInternal/Devices/pcbios/0/Config/LanBootRom "$BOOTSTRAP_CACHE_DIR/gpxe-1.0.1-80861004.rom"
done

# common changes to execute on all VMs
for VM in bcpc-bootstrap $VMS; do
  VBoxManage modifyvm $VM --vram 16
  VBoxManage modifyvm $VM --largepages on
  VBoxManage modifyvm $VM --nestedpaging on
  VBoxManage modifyvm $VM --vtxvpid on
  VBoxManage modifyvm $VM --hwvirtex on
  VBoxManage modifyvm $VM --ioapic on
  VBoxManage modifyvm $VM --uart1 0x3F8 4
  VBoxManage modifyvm $VM --uart2 0x2F8 3
  VBoxManage modifyvm $VM --uartmode1 disconnected
  VBoxManage modifyvm $VM --uartmode2 disconnected
done

# print out MAC addresses for cluster.txt
echo "-------------------------------------------"
echo "Use these MAC addresses to build your cluster.txt file:"
for VM in bcpc-bootstrap $VMS; do
  MAC_ADDRESS=$(VBoxManage showvminfo --machinereadable $VM | pcregrep -o1 -M '^hostonlyadapter\d="vboxnet0"$\n*^macaddress\d="(.+)"' | $SED 's/^(..)(..)(..)(..)(..)(..)$/\1:\2:\3:\4:\5:\6/')
  echo "MAC address for $VM is $MAC_ADDRESS"
done
