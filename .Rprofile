source("renv/activate.R")

# --- Dependency freeze: require explicit opt-in for snapshot/update ---
if (interactive() && requireNamespace("renv", quietly = TRUE)) {
  local({
    orig_snapshot <- renv::snapshot
    orig_update   <- renv::update

    # NOTE: assignInNamespace mutates the renv namespace at session start.
    # Caveat: if renv is reloaded (e.g. renv::load()) during the session,
    # the override is bypassed until R restarts. This is acceptable for an
    # interactive guardrail; maintainers should not rely on this for
    # automated/non-interactive pipelines.
    assignInNamespace("snapshot", function(...) {
      if (!identical(Sys.getenv("RENV_ALLOW_SNAPSHOT"), "1")) {
        stop(
          "renv::snapshot() is frozen. To update renv.lock intentionally:\n",
          "  Sys.setenv(RENV_ALLOW_SNAPSHOT = '1'); renv::snapshot()\n",
          "Or from shell: make renv_snapshot",
          call. = FALSE
        )
      }
      orig_snapshot(...)
    }, ns = "renv")

    assignInNamespace("update", function(...) {
      if (!identical(Sys.getenv("RENV_ALLOW_UPDATE"), "1")) {
        stop(
          "renv::update() is frozen. To update packages intentionally:\n",
          "  Sys.setenv(RENV_ALLOW_UPDATE = '1'); renv::update()\n",
          "Or from shell: RENV_ALLOW_UPDATE=1 Rscript -e \"renv::update()\"",
          call. = FALSE
        )
      }
      orig_update(...)
    }, ns = "renv")
  })
}
