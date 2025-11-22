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

# Repair - let renv auto-detect the project
cat("\n🔄 Initiating renv repair...\n")
renv::repair()

cat("\n🔄 Initiating renv restore...\n")
renv::restore(prompt = FALSE)
