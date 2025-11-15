# NFL Predictions - Master Script
# Run this to generate predictions

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
    archive_file <- paste0("data/predictions/predictions_", archive_date, ".csv")

    if (!file.exists(archive_file)) {
      write.csv(prev_preds, archive_file, row.names = FALSE)
      cat(paste("✓ Archived previous predictions to", archive_file, "\n\n"))
    }
  }
}

start_time <- Sys.time()

cat("STEP 1: Loading NFL data...\n")
source("scripts/01_load_data.R")
cat("\n")

cat("STEP 2: Calculating features...\n")
source("scripts/02_calculate_features.R")
cat("\n")

cat("STEP 3: Training models...\n")
source("scripts/03_train_model.R")
cat("\n")

cat("STEP 4: Generating base predictions...\n")
source("scripts/04_make_predictions.R")
cat("\n")

cat("STEP 5: Calculating defensive quality ratings...\n")
source("scripts/05_calculate_defensive_ratings.R")
cat("\n")

cat("STEP 6: Building backup QB performance database...\n")
source("scripts/08_backup_qb_performance.R")
cat("\n")

cat("STEP 7: Adjusting for injuries (opponent + QB aware)...\n")
source("scripts/06_adjust_injuries_opponent_context.R")
cat("\n")

cat("STEP 8: Integrating weather forecasts...\n")
source("scripts/07_integrate_weather.R")
cat("\n")

#cat("STEP 9: Calculating recent form and momentum...\n")
#source("scripts/09_recent_form.R")cat("\n")

end_time <- Sys.time()
elapsed <- round(difftime(end_time, start_time, units = "mins"), 2)

cat("========================================\n")
cat(paste("✓ PIPELINE COMPLETE in", elapsed, "minutes\n"))
cat("========================================\n")

# Save with appropriate naming
if (run_type == "primary") {
  dated_file <- paste0("data/predictions/predictions_primary_", Sys.Date(), ".csv")
} else if (run_type == "tracking") {
  dated_file <- paste0("data/predictions/predictions_tracking_", Sys.Date(), ".csv")
} else {
  dated_file <- paste0("data/predictions/predictions_manual_", Sys.Date(), ".csv")
}

# Load the final predictions from weather script
predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)
write.csv(predictions, dated_file, row.names = FALSE)

cat("\nYour predictions are saved in:\n")
cat("  data/predictions/latest_predictions.csv\n")
cat(paste(" ", dated_file, "\n"))