# Repository Guidelines

## Project Structure & Module Organization
`power-os` is a BlueBuild-based Fedora Atomic image, not a conventional app. The main image definition lives in `recipes/recipe.yaml`, with reusable recipe fragments in `recipes/modules/*.yaml`. Custom build modules live in `modules/<name>/` and usually pair `module.yaml` metadata with a Nushell runner such as `rust-build.nu` or `zig-build.nu`. Static system files belong in `files/system/`, helper scripts in `files/scripts/`, and local patch files in `files/patches/`. CI is defined in `.github/workflows/build.yml`.

`recipes/modules/prebuilt-assets.yaml` is a special integration point. It pulls release tarballs such as `rmpc`, `awww`, `tree-sitter`, `nvim`, and `aria2` from the separate `binary-foundry` repository, verifies SHA256 files, and extracts them into the image. Treat that repository as the prebuild pipeline: it starts from a Fedora 44 container base, builds selected tools from source, then publishes release artifacts consumed here.

## Build, Test, and Development Commands
Use BlueBuild locally before opening a PR:

```bash
bluebuild generate recipes/recipe.yaml -o Containerfile
bluebuild build -vv recipes/recipe.yaml
```

`bluebuild generate` validates the recipe structure and renders the Containerfile. `bluebuild build` performs the full local image build. For targeted review work, inspect the active recipe and modules with `sed -n '1,200p' recipes/recipe.yaml` or `rg "type:" recipes/modules modules`.

## Coding Style & Naming Conventions
Match the existing style: two-space indentation in YAML and Nushell, short comments only where behavior is non-obvious, and kebab-case file names such as `build-copy.yaml` and `rust-build.nu`. Keep module names descriptive and aligned across directory names, `module.yaml`, and copied stage names. Prefer explicit list-form commands in module configs over shell strings; the current modules treat lists as the safest override format.

## Testing Guidelines
There is no dedicated unit-test suite in this repo today. Validation is build-focused: regenerate the Containerfile, run a local BlueBuild image build, and verify any changed artifacts referenced in `recipes/modules/build-copy.yaml`, `recipes/modules/prebuilt-assets.yaml`, or `files/system/`. When changing a custom build module, exercise the affected path by building the image. If a change depends on refreshed prebuilt binaries, update release references only after the matching `binary-foundry` artifacts have been published for Fedora 44.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit style, for example `feat(package): add some more packages` and `fix(fonts): use correct name`. Use `type(scope): summary` in lowercase when practical. PRs should include a concise description, note the user-visible image impact, and link any related issue. Add screenshots only for UI-facing config changes such as Niri or Waybar behavior. Confirm the GitHub Actions build still applies; `.md`-only changes are ignored by CI.
