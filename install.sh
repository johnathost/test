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

# Install required packages for Hyper-V Enhanced Session Mode
echo "Installing hyperv-daemons and xrdp..."
apt install -y hyperv-daemons xrdp xorgxrdp

# Enable and start xrdp service
echo "Enabling and starting xrdp service..."
systemctl enable xrdp
systemctl start xrdp

# Configure xrdp to use Enhanced Session Mode
echo "Configuring xrdp for Enhanced Session Mode..."
cat << EOF > /etc/xrdp/xrdp.ini
[Globals]
ini_version=1
fork=true
port=3389
use_vsock=false
tcp_nodelay=true
security_layer=rdp
crypt_level=high
certificate=
key_file=
ssl_protocols=TLSv1.2, TLSv1.3

[xrdp1]
name=sesman-X11rdp
lib=libxrdp.so
username=ask
password=ask
ip=127.0.0.1
port=-1
code=20
EOF

# Restart xrdp to apply changes
systemctl restart xrdp

# Install PulseAudio for sound redirection
echo "Installing PulseAudio for sound redirection..."
apt install -y pulseaudio pulseaudio-module-xrdp

# Load PulseAudio xrdp modules
echo "Configuring PulseAudio for xrdp..."
cat << EOF > /etc/xrdp/pulseaudio.ini
[pulseaudio]
sink_name=xrdp-sink
source_name=xrdp-source
EOF

# Ensure PulseAudio modules are loaded for xrdp
echo "load-module module-xrdp-sink" >> /etc/pulse/default.pa
echo "load-module module-xrdp-source" >> /etc/pulse/default.pa

# Set permissions for PulseAudio
echo "Setting PulseAudio permissions..."
adduser xrdp pulse-access
adduser xrdp audio

# Enable and start PulseAudio (system-wide for xrdp)
echo "Starting PulseAudio..."
systemctl --user enable pulseaudio
systemctl --user start pulseaudio

# Configure Hyper-V integration services
echo "Ensuring Hyper-V integration services are enabled..."
cat << EOF > /etc/modules-load.d/hyperv.conf
hv_vmbus
hv_storvsc
hv_blkvsc
hv_netvsc
hv_utils
hv_balloon
EOF

# Update initramfs to include Hyper-V modules
echo "Updating initramfs..."
update-initramfs -u

# Create a script to ensure services start correctly
echo "Creating startup script for Hyper-V services..."
cat << EOF > /usr/local/bin/hyperv-enhanced.sh
#!/bin/bash
modprobe hv_vmbus
modprobe hv_storvsc
modprobe hv_blkvsc
modprobe hv_netvsc
modprobe hv_utils
modprobe hv_balloon
systemctl restart xrdp
systemctl --user restart pulseaudio
EOF

chmod +x /usr/local/bin/hyperv-enhanced.sh

# Add to systemd to run at boot
echo "Setting up systemd service for Hyper-V enhancements..."
cat << EOF > /etc/systemd/system/hyperv-enhanced.service
[Unit]
Description=Hyper-V Enhanced Session and Audio Setup
After=network.target xrdp.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hyperv-enhanced.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the custom service
systemctl enable hyperv-enhanced.service

# Final instructions
echo "Setup complete!"
echo "Please reboot the VM to apply all changes."
echo "After reboot, connect using Hyper-V Enhanced Session Mode."
echo "Ensure the Hyper-V host has 'Enhanced Session Mode' enabled in VM settings."
echo "For audio, verify that 'Audio redirection' is enabled in the RDP client."

exit 0