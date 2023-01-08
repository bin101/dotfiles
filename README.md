# My public (mac-)dotfiles

## rcm
Clone public and private repo:

    git clone git@github.com:bin101/dotfiles.git ~/.dotfiles
    git clone git@github.com:bin101/dotfiles-private.git ~/.dotfiles-private

Install [rcm](https://github.com/thoughtbot/rcm):

    brew install rcm

Init rcm:

    ~/.dotfiles/setup-rcm.bash && rcup -v


## base
use `install.sh`


## f.lux
https://justgetflux.com/

# custom
install keyboard layout and terminal profile (see custom folder)

## remove default keyboard layout
1. Change the current input source to your custom keyboard layout.
2. Open ```~/Library/Preferences/com.apple.HIToolbox.plist```. You can convert the plist to XML with ```plutil -convert xml1 ~/Library/Preferences/com.apple.HIToolbox.plist```
3. Remove the input source or input sources you want to disable from the AppleEnabledInputSources dictionary. If there is an AppleDefaultAsciiInputSource key, remove it.
4. Restart.
