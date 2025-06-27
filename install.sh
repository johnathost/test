#!/bin/bash

# Script to enable Enhanced Session Mode and sound redirection on Debian 12 VM in Hyper-V

# Exit on error
set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi

# Update package list
echo "Updating package list..."
apt update

###############################################################################
# XRDP
#

# Install required packages for Hyper-V Enhanced Session Mode
echo "Installing hyperv-daemons and xrdp..."
apt install -y hyperv-daemons xrdp

# Configure the installed XRDP ini files.
# use vsock transport.
sed -i_orig -e 's/use_vsock=true/use_vsock=false/g' /etc/xrdp/xrdp.ini
# change the port
sed -i_orig -e 's@port=3389@port=vsock://-1:3389@g' /etc/xrdp/xrdp.ini
# use rdp security.
sed -i_orig -e 's/security_layer=negotiate/security_layer=rdp/g' /etc/xrdp/xrdp.ini
# remove encryption validation.
sed -i_orig -e 's/crypt_level=high/crypt_level=none/g' /etc/xrdp/xrdp.ini
# disable bitmap compression since its local its much faster
sed -i_orig -e 's/bitmap_compression=true/bitmap_compression=false/g' /etc/xrdp/xrdp.ini

# Add script to setup the debian session properly
if [ ! -e /etc/xrdp/startdebian.sh ]; then
cat >> /etc/xrdp/startdebian.sh << EOF
#!/bin/sh
export GNOME_SHELL_SESSION_MODE=debian
export XDG_CURRENT_DESKTOP=debian:GNOME
exec /etc/xrdp/startwm.sh
EOF
chmod a+x /etc/xrdp/startdebian.sh
fi

# use the script to setup the debian session
sed -i_orig -e 's/startwm/startdebian/g' /etc/xrdp/sesman.ini

# rename the redirected drives to 'shared-drives'
sed -i -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' /etc/xrdp/sesman.ini

# Changed the allowed_users
sed -i_orig -e 's/allowed_users=console/allowed_users=anybody/g' /etc/X11/Xwrapper.config

# Blacklist the vmw module
if [ ! -e /etc/modprobe.d/blacklist_vmw_vsock_vmci_transport.conf ]; then
cat >> /etc/modprobe.d/blacklist_vmw_vsock_vmci_transport.conf <<EOF
blacklist vmw_vsock_vmci_transport
EOF
fi

#Ensure hv_sock gets loaded
if [ ! -e /etc/modules-load.d/hv_sock.conf ]; then
echo "hv_sock" > /etc/modules-load.d/hv_sock.conf
fi

# Configure the policy xrdp session
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# reconfigure the service
systemctl daemon-reload
sudo systemctl enable xrdp.service
sudo systemctl enable xrdp-sesman.service
systemctl start xrdp

#
# End XRDP
###############################################################################

###############################################################################
# Pulseaudio
#

pulsever=$(pulseaudio --version | awk '{print $2}')

sudo apt build-dep pulseaudio -y

cd /tmp
sudo apt source pulseaudio=$pulsever
cd /tmp/pulseaudio-$pulsever
sudo ./configure

git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git
cd pulseaudio-module-xrdp
sudo ./bootstrap
sudo ./configure PULSE_DIR="/tmp/pulseaudio-$pulsever"
sudo make

cd /tmp/pulseaudio-$pulsever/pulseaudio-module-xrdp/src/.libs
sudo install -t "/var/lib/xrdp-pulseaudio-installer" -D -m 644 *.so
sudo install -t "/usr/lib/pulse-$pulsever/modules" -D -m 644 *.so

#
# End Pulseaudio
###############################################################################

echo "Reboot your machine to begin using XRDP."