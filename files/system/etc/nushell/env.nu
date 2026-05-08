# env.nu
#

##############
#  Carapace  #
##############
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
let cache_file = $"($nu.cache-dir)/carapace.nu"
let carapace_bin = (which carapace | get path.0)

let need_update = (
  (not ($cache_file | path exists))
  or
  (try { (ls $carapace_bin | get modified.0) > (ls $cache_file | get modified.0) } catch { true })
)

if $need_update {
  mkdir ($nu.cache-dir | into string)
  carapace _carapace nushell | save --force $cache_file
}
