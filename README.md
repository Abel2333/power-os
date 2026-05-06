# power-os &nbsp; [![bluebuild build badge](https://github.com/abel2333/power-os/actions/workflows/build.yml/badge.svg)](https://github.com/abel2333/power-os/actions/workflows/build.yml)

`power-os` is a personal Fedora Atomic image built with BlueBuild. It is based on Fedora Kinoite 44, uses Niri as the primary desktop session, keeps KDE integration for portals and policykit, and bakes in a small set of custom-built developer tools.

## What is included

- Fedora Kinoite 44 as the base image
- Niri, Waybar, Mako, Kitty, swaylock, swayidle, and swaybg
- KDE portal integration with `xdg-desktop-portal-kde`
- `keyd` enabled by default
- `starship`, `zsh`, `nushell`, `tmux`, `ripgrep`, `fd-find`, and `eza`
- Custom-built `nvim`, `tree-sitter`, and `rmpc`
- System Flatpaks:
  - `app.zen_browser.zen`
  - `org.kde.gwenview`
  - `org.kde.dolphin`
  - `com.qq.QQ`
- Optional chezmoi integration for dotfiles bootstrap

## Installation

> [!WARNING]
> [Ostree native containers are still considered experimental by Fedora](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable).

To rebase an existing atomic Fedora installation to the latest published image:

- Rebase to the unsigned image first so the signing policy and keys are installed:
  ```bash
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/abel2333/power-os:latest
  ```
- Reboot:
  ```bash
  systemctl reboot
  ```
- Rebase to the signed image:
  ```bash
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/abel2333/power-os:latest
  ```
- Reboot again:
  ```bash
  systemctl reboot
  ```

The `latest` image tag points to the newest build of this repo. The recipe itself is currently pinned to Fedora 44 in `recipes/recipe.yaml`.

## Local Build

To generate the Containerfile locally:

```bash
bluebuild generate recipes/recipe.yaml -o Containerfile
```

To build the image locally:

```bash
bluebuild build -vv recipes/recipe.yaml
```

## Chezmoi

The image installs BlueBuild's `chezmoi` module, configured to use [`Abel2333/dotfiles`](https://github.com/Abel2333/dotfiles). With the current configuration, the user services are installed but not enabled globally for all users.

After rebasing to this image, enable `chezmoi` for your own user with:

```bash
systemctl enable --user chezmoi-init.service chezmoi-update.timer
systemctl start --user chezmoi-init.service
```

To check the user units:

```bash
systemctl status --user chezmoi-init.service
systemctl status --user chezmoi-update.timer
```

The module initializes the source repo with an HTTPS remote. If you want to edit your dotfiles and push changes back over SSH, switch the remote after initialization:

```bash
chezmoi cd
git remote set-url origin git@github.com:<user>/<dotfiles-repo>.git
git remote -v
```

## ISO

If you build on Fedora Atomic, you can generate an offline ISO with the instructions in the [BlueBuild docs](https://blue-build.org/how-to/generate-iso/#_top).

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). Verify the signature with:

```bash
cosign verify --key cosign.pub ghcr.io/abel2333/power-os
```
