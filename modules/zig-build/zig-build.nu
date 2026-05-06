#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg | get -o $key | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

def zig_arch [] {
  let machine = (^uname -m | str trim)
  match $machine {
    "x86_64" => "x86_64"
    "aarch64" => "aarch64"
    "arm64" => "aarch64"
    "armv7l" => "arm"
    "armv6l" => "arm"
    "i686" => "x86"
    "i386" => "x86"
    "riscv64" => "riscv64"
    "ppc64le" => "powerpc64le"
    "s390x" => "s390x"
    _ => (fail $"zig-build: unsupported architecture for Zig download: ($machine)")
  }
}

def install_zig [version] {
  let arch = (zig_arch)
  let install_dir = ([$"/tmp" $"zig-($version)"] | path join)
  let tarball = ([$"/tmp" $"zig-($arch)-linux-($version).tar.xz"] | path join)
  let url = $"https://ziglang.org/download/($version)/zig-($arch)-linux-($version).tar.xz"

  ^rm -rf $install_dir
  ^mkdir -p $install_dir
  ^curl --fail --show-error --location --retry 5 --retry-delay 2 --retry-all-errors $url -o $tarball
  ^tar -xJf $tarball -C $install_dir --strip-components=1

  $install_dir
}

# 统一生成产物清单：默认 zig-out/bin/<zig_bin> + 附加 artifacts
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

def run_build [clone_dir, build_cmd, zig_dir] {
  let build_cmd_type = ($build_cmd | describe)
  let env_columns = ($env | columns)
  let raw_path = (
    if ($env_columns | any {|c| $c == "PATH" }) {
      $env | get PATH
    } else if ($env_columns | any {|c| $c == "Path" }) {
      $env | get Path
    } else {
      "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  )
  let current_path = (
    if (($raw_path | describe | str starts-with "list<")) {
      $raw_path | str join ":"
    } else {
      $raw_path | into string
    }
  )
  let path_with_zig = (
    if ($zig_dir | is-empty) {
      $current_path
    } else {
      let zig_bin_dir = ([$zig_dir] | path join)
      if (($current_path | split row ":" | any {|p| $p == $zig_bin_dir })) {
        $current_path
      } else if ($current_path | is-empty) {
        $zig_bin_dir
      } else {
        $"($zig_bin_dir):($current_path)"
      }
    }
  )

  with-env { PATH: $path_with_zig } {
    # 在源码目录执行构建，保证相对路径和 build.zig 可见
    cd $clone_dir

    if (($build_cmd_type | str starts-with "list<")) {
      if (($build_cmd | length) == 0) {
  # 默认优化级别使用 ReleaseFast
  ^zig build -Doptimize=ReleaseFast
      } else {
        let cmd = (($build_cmd | first) | into string)
  if ($cmd | is-empty) {
          fail "zig-build: 'build_cmd' list cannot start with an empty command"
        }
        let args = ($build_cmd | skip 1 | each {|arg| $arg | into string })
        run-external $cmd ...$args
      }
    } else if ($build_cmd_type == "string") {
      if ($build_cmd | is-empty) {
        ^zig build -Doptimize=ReleaseFast
      } else {
  # string 形式兼容旧配置，交给 bash 解释
        ^bash -lc $build_cmd
  }
    } else {
      fail "zig-build: 'build_cmd' must be a string or list"
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

    # 相对路径按 clone_dir 解析，绝对路径原样使用
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
      # Directory artifact: treat 'dest' as target directory and copy all contents.
      ^mkdir -p $dest
      ^cp -a $"($source_path)/." $"($dest)/"
    } else {
      ^install $"-Dm($mode)" $source_path $dest
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
  let zig_version = (cfg_get $cfg "zig_version" "")
  let enable_updates_testing = (cfg_get $cfg "enable_updates_testing" false)
  let build_cmd = (cfg_get $cfg "build_cmd" [])
  let output_bin = (cfg_get $cfg "output_bin" "")
  let extra_artifacts = (cfg_get $cfg "artifacts" [])

  let artifacts = (collect_artifacts $output_bin $zig_bin $extra_artifacts)
  if (($artifacts | length) == 0) {
    fail "zig-build: no install targets; set 'output_bin' or 'artifacts'"
  }

  let dnf_deps = (
    [[curl gcc git tar xz] (cfg_get $cfg "dnf_deps" [])]
      | flatten
      | uniq
  )
  let dnf_deps = (
    if ($zig_version | is-empty) {
      [$dnf_deps [zig]] | flatten | uniq
    } else {
      $dnf_deps
    }
  )

  # 安装 Zig 构建所需依赖后再执行 clone/build/install
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

  let zig_dir = (
    if ($zig_version | is-empty) {
      ""
    } else {
      install_zig $zig_version
    }
  )

  run_build $clone_dir $build_cmd $zig_dir
  install_artifacts $clone_dir $artifacts
}
