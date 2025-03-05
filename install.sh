#!/bin/zsh

# Install xCode cli tools
echo "Installing commandline tools..."
xcode-select --install

# Install Brew
echo "Installing Brew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew analytics off

# Brew Taps
echo "Installing apps..."
brew bundle install --file=~/.dotfiles/Brewfile

# macOS Settings
echo "Changing macOS defaults..."
defaults write com.apple.NetworkBrowser BrowseAllInterfaces 1
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.spaces spans-displays -bool false # create spaces for all displays
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock "mru-spaces" -bool "false" # do not sort spaces by recently uses
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false # disalbe animations for opening/closing windows
defaults write com.apple.LaunchServices LSQuarantine -bool false #Turn off the “Application Downloaded from Internet” quarantine warning.
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

# Installing Fonts
curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/latest/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf

# SbarLua
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua/ && make install && rm -rf /tmp/SbarLua/)

# Copying and checking out configuration files
echo "Planting Configuration Files..."
rcup -v
source $HOME/.zshrc

# Start Services
echo "Starting Services (grant permissions)..."
brew services start felixkratz/formulae/sketchybar

echo "For the system Java wrappers to find this JDK, symlink it with:\n 'sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk'"
echo "Make volume icon in status bar always available in control center"
echo "Installation complete please restart..."

