# NFL Predictions - Master Script
# Run this to generate predictions
# v2 IMPROVEMENTS:
# - Added error handling for each pipeline step
# - Marks critical vs optional steps
# - Logs all errors for debugging

# Load error handling utilities
source("scripts/00_error_handling.R")

# Determine run type from environment variable
run_type <- Sys.getenv("RUN_TYPE", "manual")

# Configure file paths based on run type (centralized configuration)
if (run_type == "tracking") {
  latest_file <- "data/predictions/latest_tracking.csv"
  run_prefix <- "tracking"
} else {
  latest_file <- "data/predictions/latest_predictions.csv"
  run_prefix <- ifelse(run_type == "primary", "primary", "manual")
}

# Export for scripts to use
Sys.setenv(LATEST_FILE = latest_file)
Sys.setenv(RUN_PREFIX = run_prefix)

cat("========================================\n")
cat(paste("NFL PREDICTIONS MODEL -", toupper(run_type), "RUN\n"))
cat(paste("Output file:", latest_file, "\n"))
cat("========================================\n\n")

# Archive previous predictions before generating new ones (primary/manual runs only)
if (run_type != "tracking" && file.exists(latest_file)) {
  prev_preds <- read.csv(latest_file, stringsAsFactors = FALSE)
  if (nrow(prev_preds) > 0) {
    archive_date <- unique(prev_preds$prediction_date)[1]
    archive_subdir <- paste0("data/predictions/", run_prefix, "/")
    archive_file <- paste0(archive_subdir, "predictions_", archive_date, ".csv")

    # Create subdirectory if it doesn't exist
    if (!dir.exists(archive_subdir)) {
      dir.create(archive_subdir, recursive = TRUE)
    }

    if (!file.exists(archive_file)) {
      write.csv(prev_preds, archive_file, row.names = FALSE)
      cat(paste("✓ Archived previous predictions to", archive_file, "\n\n"))
    }
  }
}

start_time <- Sys.time()

# Execute pipeline steps with error handling
# Critical steps (required=TRUE) will stop pipeline on failure
# Optional steps (required=FALSE) will continue with degraded predictions

step1_success <- safe_execute_step(
  step_number = 1,
  step_name = "Loading NFL data",
  script_path = "scripts/01_load_data.R",
  required = TRUE,  # CRITICAL: Can't continue without data
  run_type = run_type
)

step2_success <- safe_execute_step(
  step_number = 2,
  step_name = "Calculating features",
  script_path = "scripts/02_calculate_features.R",
  required = TRUE,  # CRITICAL: Need features for training
  run_type = run_type
)

step3_success <- safe_execute_step(
  step_number = 3,
  step_name = "Training models",
  script_path = "scripts/03_train_model.R",
  required = TRUE,  # CRITICAL: Need trained models
  run_type = run_type
)

step4_success <- safe_execute_step(
  step_number = 4,
  step_name = "Generating base predictions",
  script_path = "scripts/04_make_predictions.R",
  required = TRUE,  # CRITICAL: Core functionality
  run_type = run_type
)

step5_success <- safe_execute_step(
  step_number = 5,
  step_name = "Calculating defensive quality ratings",
  script_path = "scripts/05_calculate_defensive_ratings.R",
  required = FALSE,  # OPTIONAL: Enhances injury adjustments
  run_type = run_type
)

step6_success <- safe_execute_step(
  step_number = 6,
  step_name = "Building backup QB performance database",
  script_path = "scripts/08_backup_qb_performance.R",
  required = FALSE,  # OPTIONAL: Enhances injury adjustments
  run_type = run_type
)

step7_success <- safe_execute_step(
  step_number = 7,
  step_name = "Adjusting for injuries (opponent + QB aware)",
  script_path = "scripts/06_adjust_injuries_opponent_context.R",
  required = FALSE,  # OPTIONAL: Base predictions work without it
  run_type = run_type
)

step8_success <- safe_execute_step(
  step_number = 8,
  step_name = "Integrating weather forecasts",
  script_path = "scripts/07_integrate_weather.R",
  required = FALSE,  # OPTIONAL: Base predictions work without it
  run_type = run_type
)

#step9_success <- safe_execute_step(
#  step_number = 9,
#  step_name = "Calculating recent form and momentum",
#  script_path = "scripts/09_recent_form.R",
#  required = FALSE,
#  run_type = run_type
#)

end_time <- Sys.time()
elapsed <- round(difftime(end_time, start_time, units = "mins"), 2)

# Report any optional step failures
failed_steps <- c()
if (!step5_success) failed_steps <- c(failed_steps, "Defensive ratings")
if (!step6_success) failed_steps <- c(failed_steps, "QB performance database")
if (!step7_success) failed_steps <- c(failed_steps, "Injury adjustments")
if (!step8_success) failed_steps <- c(failed_steps, "Weather integration")

if (length(failed_steps) > 0) {
  cat("\n⚠️  WARNING: Some optional steps failed:\n")
  for (step in failed_steps) {
    cat(paste("  -", step, "\n"))
  }
  cat("Predictions generated with degraded accuracy.\n")
  cat("Check error_log.csv for details.\n\n")
}

cat("========================================\n")
cat(paste("✓ PIPELINE COMPLETE in", elapsed, "minutes\n"))
cat("========================================\n")

# Save with appropriate naming in subdirectories
if (run_type == "primary") {
  subdir <- "data/predictions/primary/"
  dated_file <- paste0(subdir, "predictions_primary_", Sys.Date(), ".csv")
} else if (run_type == "tracking") {
  subdir <- "data/predictions/tracking/"
  dated_file <- paste0(subdir, "predictions_tracking_", Sys.Date(), ".csv")
} else {
  subdir <- "data/predictions/manual/"
  dated_file <- paste0(subdir, "predictions_manual_", Sys.Date(), ".csv")
}

# Create subdirectory if it doesn't exist
if (!dir.exists(subdir)) {
  dir.create(subdir, recursive = TRUE)
}

# Load the final predictions from weather script
predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)
write.csv(predictions, dated_file, row.names = FALSE)

cat("\nYour predictions are saved in:\n")
cat("  data/predictions/latest_predictions.csv\n")
cat(paste(" ", dated_file, "\n"))