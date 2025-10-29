# Test Runner for NFL Predictions Model
# Installs testthat if needed and runs all tests

cat("NFL Predictions Model - Test Suite\n")
cat("===================================\n\n")

# Set working directory to project root (parent of tests/)
if (basename(getwd()) == "tests") {
  setwd("..")
}

cat(paste("Working directory:", getwd(), "\n"))

# Install testthat if not already installed
if (!require("testthat", quietly = TRUE)) {
  cat("Installing testthat package...\n")
  install.packages("testthat", repos = "https://cloud.r-project.org/")
  library(testthat)
} else {
  library(testthat)
}

# Run all tests
cat("\nRunning tests...\n\n")
test_dir("tests", reporter = "progress")

cat("\n✓ Testing complete\n")
