
# This script is utilized by Makefile, it's not intended to be run by humans

set -eo pipefail

if [[ ! -r "cidata.ssh.pub" ]]; then
    echo "ERROR: Expectinbg to find the file $PWD/cidata.ssh.pub existing and readable.
"
    exit 1
fi

cat <<EOF > user-data
#cloud-config
timezone: US/Central
growpart:
    mode: auto
disable_root: false
ssh_pwauth: True
ssh_import_id: [root]
ssh_authorized_keys:
    - $(cat cidata.ssh.pub)
users:
   - name: root
     primary-group: root
     homedir: /root
     system: true
EOF
