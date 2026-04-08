#!/bin/zsh
set -e

DOTFILES_DIR="$HOME/.dotfiles"

if [ ! -d "$DOTFILES_DIR" ]; then
  echo "Error: Dotfiles directory not found at $DOTFILES_DIR"
  echo "Please clone the repo to $DOTFILES_DIR first."
  exit 1
fi

# Install xCode cli tools
if ! xcode-select -p &>/dev/null; then
  echo "Installing commandline tools..."
  xcode-select --install
  echo "Waiting for Xcode CLI Tools installation to complete..."
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  echo "Xcode CLI Tools installed."
else
  echo "Xcode CLI Tools already installed."
fi

# Install Brew
if ! command -v brew &>/dev/null; then
  echo "Installing Brew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "Brew already installed."
fi

brew analytics off

# Prompt to log in to App Store (required for mas)
echo "Please make sure you are logged in to the App Store (required for mas installs)."
echo "Press Enter to continue..."
read -r

# Install apps via Brewfile
echo "Installing apps..."
brew bundle install --file="$DOTFILES_DIR/Brewfile"

# Install lua packages
echo "Installing Lua packages..."
luarocks install luasocket luasec dkjson

# macOS Settings
echo "Changing macOS defaults..."
defaults write com.apple.NetworkBrowser BrowseAllInterfaces 1
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.spaces spans-displays -bool true # just one space all displays
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock "mru-spaces" -bool "false" # do not sort spaces by recently uses
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false # disable animations for opening/closing windows
defaults write com.apple.LaunchServices LSQuarantine -bool false # turn off the "Application Downloaded from Internet" quarantine warning
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain _HIHideMenuBar -bool true
defaults write NSGlobalDomain AppleHighlightColor -string "0.65098 0.85490 0.58431"
defaults write NSGlobalDomain AppleAccentColor -int 1
defaults write com.apple.screencapture location -string "$HOME/Desktop"
defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.finder DisableAllAnimations -bool true
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder ShowStatusBar -bool false
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder CreateDesktop -bool false
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool YES

killall Finder
killall SystemUIServer

# SbarLua
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua/ && make install && rm -rf /tmp/SbarLua/)

# Copying and checking out configuration files
echo "Planting Configuration Files..."
rcup -v

# Start Services
echo "Starting Services (grant permissions)..."
brew services start felixkratz/formulae/sketchybar

echo ""
echo "=== Post-install manual steps ==="
echo "1. Symlink JDK: sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk"
echo "2. Make volume icon in status bar always available in control center"
echo "3. Installation complete — please restart your Mac."
