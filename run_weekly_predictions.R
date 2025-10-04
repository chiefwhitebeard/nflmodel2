# NFL Predictions - Master Script
# Run this to generate predictions

# Determine run type from environment variable
run_type <- Sys.getenv("RUN_TYPE", "manual")

cat("========================================\n")
cat(paste("NFL PREDICTIONS MODEL -", toupper(run_type), "RUN\n"))
cat("========================================\n\n")

# Archive previous predictions before generating new ones
if (file.exists("data/predictions/latest_predictions.csv")) {
  prev_preds <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)
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

# Archive previous predictions before generating new ones
if (file.exists("data/predictions/latest_predictions.csv")) {
  prev_preds <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)
  if (nrow(prev_preds) > 0) {
    # Use prediction_date from the file for archive filename
    archive_date <- unique(prev_preds$prediction_date)[1]
    archive_file <- paste0("data/predictions/predictions_", archive_date, ".csv")
    
    # Only archive if this dated file doesn't exist
    if (!file.exists(archive_file)) {
      write.csv(prev_preds, archive_file, row.names = FALSE)
      cat(paste("✓ Archived previous predictions to", archive_file, "\n\n"))
    }
  }
}

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