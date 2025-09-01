#!/usr/bin/env Rscript

# * check to ensure renv install
if (!require("renv", quietly = TRUE)) {
    install.packages("renv")
}

# import packages
library(renv)

# Repair and restore in same session
cat("\n🔄 Initiating renv repair...\n")
renv::repair(project = "../", lockfile = "../renv.lock")

cat("\n🔄 Initiating renv restore...\n")
renv::restore(project = "../", lockfile = "../renv.lock", prompt = FALSE)
