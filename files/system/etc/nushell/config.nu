# config.nu
#

# Functions
def --env _ls_targets [...paths: string] {
    if ($paths | is-empty) {
        ["."]
    } else {
        $paths | each { |p| $p | path expand }
    }
}

def _ls_relativize [result: table, targets: list<string>] {
    if ($targets == ["."]) {
        return $result
    }

    if ($targets | length) == 1 {
        let base = $targets | first
        return ($result | update name { |row| $row.name |  path relative-to $base })
    }

    return result
}

def l [...paths: string] {
    let targets = _ls_targets ...$paths
    ls --all --long ...$targets
    | select name type mode group user size modified
    | _ls_relativize $in $targets
}
def ll [...paths: string] {
    let targets = _ls_targets ...$paths
    ls --long ...$targets
    | select name type mode group user size modified
    | _ls_relativize $in $targets
}

# Carapace
source $"($nu.cache-dir)/carapace.nu"
