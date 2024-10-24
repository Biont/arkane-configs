echo "Setting up Waydroid"
waydroid init -s GAPPS
systemctl enable waydroid-container.service
waydroid prop set persist.waydroid.multi_windows true
waydroid-extras -a 13 install libndk
waydroid-extras -a 13 install widevine
