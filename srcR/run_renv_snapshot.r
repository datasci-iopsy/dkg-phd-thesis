#!/usr/bin/env Rscript

# * check to ensure renv install
if (!require("renv", quietly = TRUE)) {
    install.packages("renv")
}

# import packages
library(renv)

# Initialize renv
renv::snapshot()
