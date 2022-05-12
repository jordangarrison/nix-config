# My Nix Configuration

To set up please do the following:

1. Clone the repository to your local machine.
2. Run `git crypt unlock` to unlock secrets folder
3. Update the `<folder>.example.sed` files with your own values and place them in `.secrets/<folder>.sed`.
4. Run `./update-config.sh` to update the configuration files.

## Scripts

### `./update-config.sh`

This is a helper script which will update the configuration files, not used for installation.

```sh
./update-config.sh [[-d]] [folder]
```

- `-d`: Dry run.
- `folder`: The folder to update /etc/nixos/configuration.nix with.

### `./update-users.sh`

This is a helper script which will run home manager for the currently logged in user if they are in the repo.

```sh
./update-users.sh
```

### `./update-channels.sh`

This script when run will update the nixos channels.

### `./update-home-channels.sh`

This script when run will update the home-manager channels.
