# Windows Git config

Setup connects this directory to `%USERPROFILE%\.config\git` with a junction.
Git reads `config` automatically. An existing `%USERPROFILE%\.gitconfig` is
untouched and takes precedence.

The shared identity and LF line endings are retained from the previous setup.
Machine-specific settings belong in `config.local`, which is included by
`config` and ignored by this repository. Setup preserves an existing
`config.local` when replacing an older Git config directory.

Commit signing is opt-in so a new machine can commit without an SSH signing key.
After creating your own key, enable signing in `config.local`:

```gitconfig
[commit]
    gpgsign = true
[gpg]
    format = ssh
[user]
    signingkey = ~/.ssh/id_ed25519.pub
```

Private keys and credentials must never be stored in this repository.
