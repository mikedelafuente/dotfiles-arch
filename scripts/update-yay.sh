# Remove the broken yay
sudo pacman -R yay

# Install base-devel if you don't have it
sudo pacman -S --needed base-devel git

# Clone and build yay from source
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
