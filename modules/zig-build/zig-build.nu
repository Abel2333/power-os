#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg | get -o $key | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

def collect_artifacts [output_bin, zig_bin, extra_artifacts] {
  let default_artifact = (
    if ($output_bin | is-empty) {
      []
    } else {
      [{
        source: $"zig-out/bin/($zig_bin)"
        dest: $output_bin
        mode: "755"
      }]
    }
  )

  [$default_artifact $extra_artifacts] | flatten
}

def apply_patches [clone_dir, patches] {
  let patches_type = ($patches | describe)
  if not ($patches_type | str starts-with "list<") {
    fail "zig-build: 'patches' must be a list of patch file paths"
  }

  cd $clone_dir

  for patch in $patches {
    let patch_path = ($patch | into string)
    if ($patch_path | is-empty) {
      fail "zig-build: 'patches' entries cannot be empty"
    }
    if not ($patch_path | str starts-with "/") {
      fail "zig-build: patch paths must be absolute, for example /tmp/files/patches/example.patch"
    }

    let patch_type = (
      try {
        $patch_path | path type
      } catch {
        ""
      }
    )
    if $patch_type != "file" {
      fail $"zig-build: patch file not found: ($patch_path)"
    }

    ^git apply --verbose $patch_path
  }
}

def log_build_context [clone_dir, repository, branch, patches, zig_version] {
  cd $clone_dir

  let commit = (^git rev-parse HEAD | str trim)
  let system_zig_version = (^zig version | str trim)
  let patch_count = ($patches | length)

  print $"zig-build: repository=($repository)"
  if ($branch | is-not-empty) {
    print $"zig-build: branch=($branch)"
  }
  print $"zig-build: commit=($commit)"
  print $"zig-build: system-zig=($system_zig_version)"
  if ($zig_version | is-not-empty) {
    print $"zig-build: requested-zig=($zig_version) via anyzig"
  }
  if $patch_count > 0 {
    print $"zig-build: patches=($patch_count)"
  }
}

def setup_anyzig [zig_version] {
  if ($zig_version | is-empty) {
    return null
  }

  let anyzig_dir = "/tmp/anyzig"
  let anyzig_bin = "/tmp/anyzig/zig-out/bin"

  ^rm -rf $anyzig_dir
  ^git clone --depth 1 https://github.com/marler8997/anyzig.git $anyzig_dir

  do {
    cd $anyzig_dir
    ^zig build -Doptimize=ReleaseFast
  }

  {
    bin_dir: $anyzig_bin
    requested_version: $zig_version
  }
}

def inject_zig_version [build_cmd, zig_version] {
  if ($zig_version | is-empty) {
    return $build_cmd
  }

  let build_cmd_type = ($build_cmd | describe)
  if not ($build_cmd_type | str starts-with "list<") {
    return $build_cmd
  }

  if (($build_cmd | length) == 0) {
    return [zig $zig_version build -Doptimize=ReleaseFast]
  }

  let cmd = (($build_cmd | first) | into string)
  if $cmd == "zig" {
    return ([zig $zig_version] | append ($build_cmd | skip 1))
  }

  $build_cmd
}

def current_path_string [] {
  let default_system_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  let env_columns = ($env | columns)
  let raw_path = (
    if ($env_columns | any {|c| $c == "PATH" }) {
      $env | get PATH
    } else if ($env_columns | any {|c| $c == "Path" }) {
      $env | get Path
    } else {
      $default_system_path
    }
  )

  if (($raw_path | describe | str starts-with "list<")) {
    $raw_path | str join ":"
  } else {
    $raw_path | into string
  }
}

def run_build [clone_dir, build_cmd, zig_version, anyzig_ctx] {
  let effective_cmd = (inject_zig_version $build_cmd $zig_version)

  cd $clone_dir

  let run = {|cmd_to_run|
    let cmd_type = ($cmd_to_run | describe)
    if (($cmd_type | str starts-with "list<")) {
      if (($cmd_to_run | length) == 0) {
        if ($zig_version | is-empty) {
          ^zig build -Doptimize=ReleaseFast
        } else {
          ^zig $zig_version build -Doptimize=ReleaseFast
        }
      } else {
        let cmd = (($cmd_to_run | first) | into string)
        if ($cmd | is-empty) {
          fail "zig-build: 'build_cmd' list cannot start with an empty command"
        }
        let args = ($cmd_to_run | skip 1 | each {|arg| $arg | into string })
        run-external $cmd ...$args
      }
    } else if ($cmd_type == "string") {
      if ($cmd_to_run | is-empty) {
        if ($zig_version | is-empty) {
          ^zig build -Doptimize=ReleaseFast
        } else {
          ^zig $zig_version build -Doptimize=ReleaseFast
        }
      } else {
        ^bash -lc $cmd_to_run
      }
    } else {
      fail "zig-build: 'build_cmd' must be a string or list"
    }
  }

  if ($anyzig_ctx | is-empty) {
    do $run $effective_cmd
  } else {
    let anyzig_bin_dir = ($anyzig_ctx | get bin_dir)
    let path_with_anyzig = $"($anyzig_bin_dir):(current_path_string)"
    with-env { PATH: $path_with_anyzig } {
      do $run $effective_cmd
    }
  }
}

def install_artifacts [clone_dir, artifacts] {
  for artifact in $artifacts {
    let source = ($artifact | get -o source | default "")
    let dest = ($artifact | get -o dest | default "")
    let mode = (($artifact | get -o mode | default "644") | into string)

    if ($source | is-empty) {
      fail "zig-build: each artifact requires 'source'"
    }
    if ($dest | is-empty) {
      fail "zig-build: each artifact requires 'dest'"
    }

    let source_path = (
      if ($source | str starts-with "/") {
        $source
      } else {
        ([$clone_dir $source] | path join)
      }
    )

    let source_type = (
      try {
        $source_path | path type
      } catch {
        ""
      }
    )

    if ($source_type == "dir") {
      ^mkdir -p $dest
      ^cp -a $"($source_path)/." $"($dest)/"
    } else if ($source_type == "file") {
      ^install $"-Dm($mode)" $source_path $dest
    } else {
      fail $"zig-build: artifact source not found: ($source_path)"
    }
  }
}

def main [config] {
  let cfg = ($config | from json)

  let repository = (cfg_get $cfg "repository" "")
  if ($repository | is-empty) {
    fail "zig-build: 'repository' is required"
  }

  let zig_bin = (cfg_get $cfg "zig_bin" "")
  if ($zig_bin | is-empty) {
    fail "zig-build: 'zig_bin' is required"
  }

  let branch = (cfg_get $cfg "branch" "")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/zig-build")
  let enable_updates_testing = (cfg_get $cfg "enable_updates_testing" false)
  let build_cmd = (cfg_get $cfg "build_cmd" [])
  let output_bin = (cfg_get $cfg "output_bin" "")
  let extra_artifacts = (cfg_get $cfg "artifacts" [])
  let patches = (cfg_get $cfg "patches" [])
  let zig_version = (cfg_get $cfg "zig_version" "")

  let artifacts = (collect_artifacts $output_bin $zig_bin $extra_artifacts)
  if (($artifacts | length) == 0) {
    fail "zig-build: no install targets; set 'output_bin' or 'artifacts'"
  }

  let dnf_deps = (
    [[curl gcc git tar xz] (cfg_get $cfg "dnf_deps" [])]
      | flatten
      | uniq
  )
  let dnf_deps = ([$dnf_deps [zig]] | flatten | uniq)

  if $enable_updates_testing {
    ^dnf install -y --enablerepo=updates-testing ...($dnf_deps)
  } else {
    ^dnf install -y ...($dnf_deps)
  }

  ^rm -rf $clone_dir
  if ($branch | is-not-empty) {
    ^git clone --depth 1 --branch $branch $repository $clone_dir
  } else {
    ^git clone --depth 1 $repository $clone_dir
  }

  let anyzig_ctx = (setup_anyzig $zig_version)
  apply_patches $clone_dir $patches
  log_build_context $clone_dir $repository $branch $patches $zig_version
  run_build $clone_dir $build_cmd $zig_version $anyzig_ctx
  install_artifacts $clone_dir $artifacts
}
