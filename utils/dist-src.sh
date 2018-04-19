#/bin/bash
hash -r
set -e

dir="$(git rev-parse --show-toplevel)" || exit 2
VM_BOOTSTRAP_CONFIG="$(
  cd "${dir}/bootstrap/vagrant_scripts"
  vagrant ssh-config bootstrap
)"

keyfile="$(awk '
    /Host bootstrap/,/^$/{ if ($0 ~ /^ +IdentityFile/) print $2}
  ' <<< "$VM_BOOTSTRAP_CONFIG"
)"
port="$(awk '
    /Host bootstrap/,/^$/{ if ($0 ~ /^ +Port/) print $2}
  ' <<< "$VM_BOOTSTRAP_CONFIG"
)"

rsync -axSHvP -e "ssh -oPort=$port -ostricthostkeychecking=no -i ${keyfile}" --exclude vbox --exclude vmware --exclude vbox/insecure_private_key --exclude .chef . vagrant@127.0.0.1:chef-bcpc
