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
apt install -y hyperv-daemons xrdp xorgxrdp

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

# Load Hyper-V Kernal Modules
if [ ! -e /etc/modules-load.d/hyperv.conf ]; then
cat << EOF > /etc/modules-load.d/hyperv.conf
hv_sock
hv_vmbus
hv_storvsc
hv_blkvsc
hv_netvsc
hv_utils
hv_balloon
EOF
fi

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

sudo apt install build-essential dpkg-dev libpulse-dev git autoconf libtool libltdl-dev

cd ~

git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git
cd pulseaudio-module-xrdp

sudo scripts/install_pulseaudio_sources_apt_wrapper.sh 

sudo ./bootstrap && ./configure PULSE_DIR=$HOME/pulseaudio.src
sudo make
sudo make install

#
# End Pulseaudio
###############################################################################

echo "Reboot your machine to begin using XRDP."