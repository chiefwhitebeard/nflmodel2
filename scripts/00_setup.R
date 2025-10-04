# NFL Predictions Model - Setup Script
# This script installs all required packages
# Run this ONCE when setting up the project

cat("Installing required packages for NFL predictions model...\n")

# List of required packages
packages <- c(
  "nflreadr",      # For getting NFL data
  "dplyr",         # Data manipulation
  "tidyr",         # Data tidying
  "lubridate",     # Date handling
  "purrr",         # Functional programming
  "glmnet"         # For modeling
)

# Function to install packages if not already installed
install_if_missing <- function(package) {
  if (!require(package, character.only = TRUE, quietly = TRUE)) {
    cat(paste("Installing", package, "...\n"))
    install.packages(package, repos = "https://cloud.r-project.org/")
  } else {
    cat(paste(package, "is already installed.\n"))
  }
}

# Install all packages
invisible(lapply(packages, install_if_missing))

cat("\n✓ All packages installed successfully!\n")
cat("You can now run the other scripts.\n")