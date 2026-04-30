# Windows 11 dotfiles — task runner
# Run `just` or `just --list` to see all targets

# Default: list all targets
default:
    @just --list

# Install all packages via winget, then fonts via oh-my-posh
packages:
    winget import --import-file config/packages.json --accept-source-agreements --accept-package-agreements --disable-interactivity
    oh-my-posh font install meslo
