# Set PATH, MANPATH, etc., for Homebrew.
eval "$(/opt/homebrew/bin/brew shellenv)"
if command -v rbenv >/dev/null 2>&1; then
	eval "$(rbenv init - --no-rehash zsh)"
fi
export PATH="$PATH:$HOME/.local/bin"
