# My Nix Configuration

To set up please do the following:

1. Clone the repository to your local machine.
2. Update the .env.example.sed files with your own values.
3. Run './update-config.sh' to update the configuration files.

## `./update-config.sh`

This is a helper script which will update the configuration files, not used for installation.

```sh
./update-config.sh [[-d]] [folder]
```

- `-d`: Dry run.
- `folder`: The folder to update /etc/nixos/configuration.nix with.