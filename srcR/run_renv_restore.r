#!/usr/bin/env Rscript

# * check to ensure renv install
if (!require("renv", quietly = TRUE)) {
    install.packages("renv")
}

# import packages
library(renv)

# Initialize renv
cat("\n🔄 Initiating renv restore...\n")
renv::restore(project = "../", lockfile = "../renv.lock")

cat("\n✅ R environment restored using renv...\n")
