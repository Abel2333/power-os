#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg | get -o $key | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

def apply_patches [clone_dir, patches] {
  let patches_type = ($patches | describe)
  if not ($patches_type | str starts-with "list<") {
    fail "make-build: 'patches' must be a list of patch file paths"
  }

  cd $clone_dir

  for patch in $patches {
    let patch_path = ($patch | into string)
    if ($patch_path | is-empty) {
      fail "make-build: 'patches' entries cannot be empty"
    }
    if not ($patch_path | str starts-with "/") {
      fail "make-build: patch paths must be absolute, for example /tmp/files/patches/example.patch"
    }

    let patch_type = (
      try {
        $patch_path | path type
      } catch {
        ""
      }
    )
    if $patch_type != "file" {
      fail $"make-build: patch file not found: ($patch_path)"
    }

    ^git apply --verbose $patch_path
  }
}

def log_build_context [clone_dir, repository, branch, patches] {
  cd $clone_dir

  let commit = (^git rev-parse HEAD | str trim)
  let patch_count = ($patches | length)

  print $"make-build: repository=($repository)"
  if ($branch | is-not-empty) {
    print $"make-build: branch=($branch)"
  }
  print $"make-build: commit=($commit)"
  if $patch_count > 0 {
    print $"make-build: patches=($patch_count)"
  }
}

def run_build [clone_dir, build_cmd] {
  let build_cmd_type = ($build_cmd | describe)

  cd $clone_dir

  if (($build_cmd_type | str starts-with "list<")) {
    if (($build_cmd | length) == 0) {
      ^make
    } else {
      let cmd = (($build_cmd | first) | into string)
      if ($cmd | is-empty) {
        fail "make-build: 'build_cmd' list cannot start with an empty command"
      }
      let args = ($build_cmd | skip 1 | each {|arg| $arg | into string })
      run-external $cmd ...$args
    }
  } else if ($build_cmd_type == "string") {
    if ($build_cmd | is-empty) {
      ^make
    } else {
      ^bash -lc $build_cmd
    }
  } else {
    fail "make-build: 'build_cmd' must be a string or list"
  }
}

def install_artifacts [clone_dir, artifacts] {
  for artifact in $artifacts {
    let source = ($artifact | get -o source | default "")
    let dest = ($artifact | get -o dest | default "")
    let mode = (($artifact | get -o mode | default "644") | into string)

    if ($source | is-empty) {
      fail "make-build: each artifact requires 'source'"
    }
    if ($dest | is-empty) {
      fail "make-build: each artifact requires 'dest'"
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
      fail $"make-build: artifact source not found: ($source_path)"
    }
  }
}

def main [config] {
  let cfg = ($config | from json)

  let repository = (cfg_get $cfg "repository" "")
  if ($repository | is-empty) {
    fail "make-build: 'repository' is required"
  }

  let branch = (cfg_get $cfg "branch" "")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/make-build")
  let build_cmd = (cfg_get $cfg "build_cmd" [])
  let patches = (cfg_get $cfg "patches" [])
  let artifacts = (cfg_get $cfg "artifacts" [])

  if (($artifacts | length) == 0) {
    fail "make-build: no install targets; set 'artifacts'"
  }

  let dnf_deps = (
    [[gcc git make] (cfg_get $cfg "dnf_deps" [])]
      | flatten
      | uniq
  )

  ^dnf install -y ...($dnf_deps)

  ^rm -rf $clone_dir
  if ($branch | is-not-empty) {
    ^git clone --depth 1 --branch $branch $repository $clone_dir
  } else {
    ^git clone --depth 1 $repository $clone_dir
  }

  apply_patches $clone_dir $patches
  log_build_context $clone_dir $repository $branch $patches
  run_build $clone_dir $build_cmd
  install_artifacts $clone_dir $artifacts
}
