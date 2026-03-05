#!/bin/bash
# Install Workspace ONE Intelligent Hub

declare -r ws1_url="https://cockpit.fleet.co/documents/workspaceone-intelligent-hub-amd64-23.10.0.5.tgz"
declare -r ws1_pkg="workspaceone-intelligent-hub-amd64-23.10.0.5.tgz"
declare -r ws1_tmp="/tmp/ws1-install"

arch-chroot $workdir bash -c "
set -e
mkdir -p $ws1_tmp
cd $ws1_tmp
curl -fsSL -o $ws1_pkg '$ws1_url'
tar xf $ws1_pkg
./install.sh
rm -rf $ws1_tmp
"

# The WS1 installer places files under /var/opt/ inside the chroot.
# arkdep stage-4 does `mv /opt /var/opt` and fails if /var/opt is non-empty.
# Merge the content back into /opt/ now; at runtime /opt -> var/opt anyway.
if [ -d "$workdir/var/opt" ] && [ -n "$(ls -A $workdir/var/opt 2>/dev/null)" ]; then
    cp -a $workdir/var/opt/. $workdir/opt/
    rm -rf $workdir/var/opt
fi

chmod +x $workdir/opt/arkane-postinstall/20-workspaceone-enroll.sh
