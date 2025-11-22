#!/usr/bin/env Rscript

# Set CRAN mirror for non-interactive sessions
local({
    r <- getOption("repos")
    r["CRAN"] <- "https://cloud.r-project.org/"
    options(repos = r)
})

# Activate renv - check multiple possible locations
if (file.exists("renv/activate.R")) {
    source("renv/activate.R")
} else if (file.exists("../renv/activate.R")) {
    source("../renv/activate.R")
} else {
    warning("renv/activate.R not found - renv may not be activated")
}

# Install renv if not available
if (!requireNamespace("renv", quietly = TRUE)) {
    install.packages("renv")
}

# Initialize renv
cat("\n🔄 Initiating renv snapshot\n")
renv::snapshot(project = "../", lockfile = "../renv.lock")
