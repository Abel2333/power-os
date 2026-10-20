# power-os &nbsp; [![bluebuild build badge](https://github.com/abel2333/power-os/actions/workflows/build.yml/badge.svg)](https://github.com/abel2333/power-os/actions/workflows/build.yml)

`power-os` is a personal Fedora Atomic image built with BlueBuild. It is based on Fedora Kinoite 44, uses Niri as the primary desktop session, keeps KDE integration for portals and policykit, and bakes in a small set of custom-built developer tools.

## What is included

- Fedora Kinoite 44 as the base image
- Niri, Waybar, Mako, Kitty, swaylock, swayidle, and swaybg
- KDE portal integration with `xdg-desktop-portal-kde`
- `gnome-keyring` plus the PAM module, so the login keyring is unlocked by `plasmalogin` at sign-in and backs Flatpak secret storage
- `keyd` enabled by default
- `mise`, `starship`, `zsh`, `nushell`, `tmux`, `ripgrep`, `fd-find`, and `eza`
- `dae` as the transparent proxy, with `sing-box` as its outbound carrier
- Custom-built `nvim`, `tree-sitter`, and `rmpc`
- System Flatpaks:
  - `app.zen_browser.zen`
  - `org.kde.gwenview`
  - `org.kde.dolphin`
  - `com.qq.QQ`
- Optional chezmoi integration for dotfiles bootstrap

## TODO

- Add a proper power profile switching flow for ThinkBook-style `low-power` / `balanced` / `performance` modes under `niri`, ideally with both a CLI entrypoint and Waybar integration.

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

## Proxy stack

`dae` is the transparent proxy and the only component that makes routing
decisions. `sing-box` runs as a bare outbound carrier: it holds one mixed
inbound on `127.0.0.1:12334` and its config contains no routing rules.

```
applications
  -> dae          eBPF transparent proxy, CN/direct/block classification
  -> socks5://127.0.0.1:12334
  -> sing-box     one selector over the configured nodes
  -> upstream nodes
```

The dae config is tracked at `files/system/etc/dae/config.dae`. It contains no
credentials and no subscription: it only points at the local sing-box inbound.

### The sing-box config is not in the image

The node list is subscription data and therefore carries credentials, so it is
generated at runtime and never committed:

| Path | Owner | Mode | Purpose |
| --- | --- | --- | --- |
| `/etc/sing-box/` | `root:sing-box` | `2750` | setgid directory, so any file written inside inherits the `sing-box` group |
| `/etc/sing-box/config.json` | `root:sing-box` | `0640` | generated config, readable by the service only |
| `/etc/subsmith/` | `root:root` | `0750` | operator input directory, created by tmpfiles |
| `/etc/subsmith/url` | `root:root` | `0600` | the subscription URL, provisioned by hand, never in the image |
| `/etc/subsmith/config.toml` | `root:root` | `0644` | deployment policy, shipped by the image |

`sing-box.service` carries `ConditionPathExists=/etc/sing-box/config.json`, so it
stays inactive rather than restart-looping until that file exists.

The generator is [`subsmith`](https://github.com/Abel2333/subsmith), built by
`binary-foundry` and extracted from a release tarball like the other prebuilt
tools:

1. `subsmith.timer` runs `subsmith.service` every six hours. The timer itself is
   generated at image build time from `[refresh]` in
   `/etc/subsmith/config.toml`, so the cadence has one definition, and a bad
   config fails the build instead of the first boot.
2. `subsmith.service` runs as root with `ProtectSystem=strict` and
   `ReadWritePaths=/etc/sing-box`. The tool writes atomically with the mode from
   the config, checks the candidate with `sing-box check`, and replaces the
   file only when the checker accepts it. An unchanged subscription produces no
   write at all.
3. `sing-box-reload.path` watches `/etc/sing-box/config.json` and starts
   `sing-box-reload.service`, which runs `systemctl reload-or-restart
   sing-box.service`. Because the generator only writes on a real change, the
   reload happens exactly then, and the first generation also starts the unit.

Provision the URL once:

```bash
sudo install -Dm600 /dev/stdin /etc/subsmith/url <<< 'https://…'
```

Never put the URL in `config.toml`: that file is part of the public image.
Never widen the generated file to `0644`: it exposes the node credentials to
every local user.

### Checking the stack

```bash
systemctl status dae.service sing-box.service subsmith.timer sing-box-reload.path
journalctl -b -u dae -u sing-box -u subsmith
sing-box check -c /etc/sing-box/config.json
```

## ISO

If you build on Fedora Atomic, you can generate an offline ISO with the instructions in the [BlueBuild docs](https://blue-build.org/how-to/generate-iso/#_top).

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). Verify the signature with:

```bash
cosign verify --key cosign.pub ghcr.io/abel2333/power-os
```
