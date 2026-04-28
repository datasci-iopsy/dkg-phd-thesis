# R project configuration — dkg-phd-thesis
#
# Package library is managed by uvr (https://github.com/nbafrank/uvr).
# Library paths are set automatically when scripts run via uvr:
#
#   make <target>              — invokes uvr run Rscript automatically
#   uvr run Rscript <script>   — direct script invocation
#   uvr run R                  — interactive session with project library
#
# To update dependencies: edit uvr.toml, then run make uvr_sync

# >>> uvr >>>
local({
  lib <- file.path(getwd(), ".uvr", "library")
  if (dir.exists(lib)) {
    .libPaths(lib)
    lock <- file.path(getwd(), "uvr.lock")
    if (file.exists(lock)) {
      lock_lines <- readLines(lock, warn = FALSE)
      n_locked <- length(grep("^\\[\\[package\\]\\]", lock_lines))
      installed <- list.dirs(lib, recursive = FALSE, full.names = FALSE)
      n_installed <- length(setdiff(installed, "uvr"))
      if (n_locked > 0 && n_installed < n_locked) {
        message("uvr: ", n_locked - n_installed, " of ", n_locked,
                " package(s) not installed. Run uvr::sync() to install.")
      } else if (n_locked > 0) {
        message("uvr: library linked (", n_installed, " packages)")
      } else {
        message("uvr: library active, but uvr.lock is empty. Run uvr::lock() to populate it.")
      }
    } else {
      message("uvr: library active, but no uvr.lock found. Run uvr::lock() to create one.")
    }
  }
})
# <<< uvr <<<
