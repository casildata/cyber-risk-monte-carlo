# Test runner; library(testthat) here also lets renv::snapshot() record it
library(testthat)
test_dir("tests/testthat", stop_on_failure = TRUE)
