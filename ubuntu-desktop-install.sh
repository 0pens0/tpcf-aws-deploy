#!/bin/bash

set -e

# --- Config ---
USERNAME="ubuntu"
PASSWORD="AUKJInjac1!2@3#"
DESKTOP_ENV="ubuntu-desktop"  # Change to xubuntu-desktop, etc. for lightweight options

echo "[+] Updating packages..."
sudo apt update && sudo apt upgrade -y

echo "[+] Installing desktop environment: $DESKTOP_ENV..."
sudo apt install -y $DESKTOP_ENV

echo "[+] Installing xrdp..."
sudo apt install -y xrdp

echo "[+] Enabling xrdp service..."
sudo systemctl enable xrdp
sudo systemctl restart xrdp

echo "[+] Allowing RDP through the firewall..."
sudo ufw allow 3389/tcp || true  # Ignore if ufw is not active

echo "[+] Setting GNOME as default session for $USERNAME..."
sudo -u "$USERNAME" bash -c 'echo "gnome-session" > ~/.xsession'

echo "[+] Setting password for $USERNAME..."
echo "$USERNAME:$PASSWORD" | sudo chpasswd

echo "[+] Creating polkit rule to allow RDP without local session..."
cat <<EOF | sudo tee /etc/polkit-1/localauthority.conf.d/02-allow-colord.conf >/dev/null
polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.color-manager.create-device" ||
       action.id == "org.freedesktop.color-manager.create-profile" ||
       action.id == "org.freedesktop.color-manager.delete-device" ||
       action.id == "org.freedesktop.color-manager.delete-profile" ||
       action.id == "org.freedesktop.color-manager.modify-device" ||
       action.id == "org.freedesktop.color-manager.modify-profile") &&
      subject.isInGroup("sudo")) {
    return polkit.Result.YES;
  }
});
EOF

echo "[✓] Complete. You can now reboot and RDP into the server as user '$USERNAME'."