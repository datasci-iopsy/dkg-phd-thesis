#!/usr/bin/env Rscript

# * check to ensure renv install
if (!require("renv", quietly = TRUE)) {
    install.packages("renv")
}

# import packages
library(renv)

# Check status of renv
cat("\n🔄 Initiating renv status...\n")
renv::status(project = "../", lockfile = "../renv.lock", cache = TRUE)

cat("\n🔄 Initiating renv diagnostics...\n")
renv::diagnostics(project = "../")
