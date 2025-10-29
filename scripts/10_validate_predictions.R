# NFL Predictions Model - Validation Script
# Validates archived predictions against actual results

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(lubridate)
})

cat("Validating predictions against actual results...\n")

# Create validation directory if needed
if (!dir.exists("data/validation")) {
  dir.create("data/validation", recursive = TRUE)
}

# Find most recent archived prediction file
prediction_files <- list.files("data/predictions", pattern = "^predictions_primary_\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE)

if (length(prediction_files) == 0) {
  cat("No archived prediction files found. Nothing to validate.\n")
  quit(save = "no", status = 0)
}

# Get most recent file
latest_archive <- prediction_files[order(prediction_files, decreasing = TRUE)][1]
cat(paste("Validating:", basename(latest_archive), "\n"))

# Load predictions
predictions <- read.csv(latest_archive, stringsAsFactors = FALSE)
predictions$game_date <- as.Date(predictions$game_date)

# Load actual results for games in prediction set
current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

schedule <- load_schedules(seasons = current_season)
schedule$gameday <- as.Date(schedule$gameday)

# Match predictions to actual results
results <- predictions %>%
  left_join(
    schedule %>% select(gameday, home_team, away_team, home_score, away_score, result),
    by = c("game_date" = "gameday", "home_team", "away_team")
  ) %>%
  filter(!is.na(home_score))  # Only completed games

if (nrow(results) == 0) {
  cat("No completed games found for validation yet.\n")
  quit(save = "no", status = 0)
}

cat(paste("Found", nrow(results), "completed games to validate\n"))

# Map prediction columns to clean "final_" columns for validation output
# Use the most adjusted version available
if ("adjusted_spread" %in% names(results)) {
  results$final_spread <- results$adjusted_spread
  cat("  Using adjusted_spread for final_spread\n")
} else if ("predicted_spread_weather_adjusted" %in% names(results)) {
  results$final_spread <- results$predicted_spread_weather_adjusted
  cat("  Using predicted_spread_weather_adjusted for final_spread\n")
} else if ("predicted_spread_injury_adjusted" %in% names(results)) {
  results$final_spread <- results$predicted_spread_injury_adjusted
  cat("  Using predicted_spread_injury_adjusted for final_spread\n")
} else {
  results$final_spread <- results$predicted_spread
  cat("  Using predicted_spread for final_spread\n")
}

# Map probability column
if ("adjusted_cover_probability" %in% names(results)) {
  results$final_cover_probability <- results$adjusted_cover_probability
} else if ("cover_probability_weather_adjusted" %in% names(results)) {
  results$final_cover_probability <- results$cover_probability_weather_adjusted
} else if ("cover_probability_injury_adjusted" %in% names(results)) {
  results$final_cover_probability <- results$cover_probability_injury_adjusted
} else if ("cover_probability" %in% names(results)) {
  results$final_cover_probability <- results$cover_probability
} else {
  results$final_cover_probability <- results$home_win_probability
}

# Calculate validation metrics using clean final columns
results <- results %>%
  mutate(
    actual_home_win = home_score > away_score,
    actual_spread = home_score - away_score,
    actual_total = home_score + away_score,

    # Use final columns
    winner_correct = (predicted_winner == home_team & actual_home_win) |
      (predicted_winner == away_team & !actual_home_win),
    spread_error = abs(final_spread - actual_spread),
    total_error = abs(predicted_total - actual_total),

    # Model bias
    model_vs_actual_diff = final_spread - actual_spread
  )

# Summary metrics
winner_accuracy <- mean(results$winner_correct, na.rm = TRUE)
spread_mae <- mean(results$spread_error, na.rm = TRUE)
total_mae <- mean(results$total_error, na.rm = TRUE)
avg_model_bias <- mean(results$model_vs_actual_diff, na.rm = TRUE)

cat("\n=== Validation Results ===\n")
cat(paste("Winner Accuracy:", round(winner_accuracy * 100, 1), "%\n"))
cat(paste("Spread MAE:", round(spread_mae, 2), "points\n"))
cat(paste("Total MAE:", round(total_mae, 2), "points\n"))
cat(paste("Model Bias:", round(avg_model_bias, 2), "points (+ favors home)\n"))

# Breakdown by adjustment stage (using actual prediction column names)
if ("predicted_spread" %in% names(results) && "predicted_spread_injury_adjusted" %in% names(results)) {
  cat("\n=== Adjustment Impact Analysis ===\n")

  base_mae <- mean(abs(results$predicted_spread - results$actual_spread), na.rm = TRUE)
  injury_mae <- mean(abs(results$predicted_spread_injury_adjusted - results$actual_spread), na.rm = TRUE)

  cat(paste("Base Model MAE:", round(base_mae, 2), "points\n"))
  cat(paste("After Injuries MAE:", round(injury_mae, 2), "points (",
            ifelse(injury_mae < base_mae, "✓ improved", "⚠ worse"), ")\n"))

  if ("predicted_spread_weather_adjusted" %in% names(results)) {
    weather_mae <- mean(abs(results$predicted_spread_weather_adjusted - results$actual_spread), na.rm = TRUE)
    cat(paste("After Weather MAE:", round(weather_mae, 2), "points (",
              ifelse(weather_mae < injury_mae, "✓ improved", "⚠ worse"), ")\n"))
  }

  if ("adjusted_spread" %in% names(results)) {
    final_mae <- mean(abs(results$adjusted_spread - results$actual_spread), na.rm = TRUE)
    cat(paste("Final Adjusted MAE:", round(final_mae, 2), "points\n"))
  }
}

# Save detailed results
validation_date <- Sys.Date()
detail_file <- paste0("data/validation/validation_detail_", validation_date, ".csv")
write.csv(results, detail_file, row.names = FALSE)
cat(paste("\n✓ Detailed results saved to", detail_file, "\n"))

# Append to accuracy log
log_entry <- data.frame(
  validation_date = validation_date,
  prediction_date = unique(predictions$prediction_date)[1],
  games_validated = nrow(results),
  winner_accuracy = winner_accuracy,
  spread_mae = spread_mae,
  total_mae = total_mae,
  model_bias = avg_model_bias,
  stringsAsFactors = FALSE
)

log_file <- "data/validation/accuracy_log.csv"
if (file.exists(log_file)) {
  log_data <- read.csv(log_file, stringsAsFactors = FALSE)
  log_data <- rbind(log_data, log_entry)
} else {
  log_data <- log_entry
}

write.csv(log_data, log_file, row.names = FALSE)
cat(paste("✓ Updated accuracy log:", log_file, "\n"))

# Performance alerts
alerts <- c()
if (winner_accuracy < 0.60) {
  alerts <- c(alerts, paste("⚠️  Winner accuracy below 60%:", round(winner_accuracy * 100, 1), "%"))
}
if (spread_mae > 12) {
  alerts <- c(alerts, paste("⚠️  Spread MAE above 12 points:", round(spread_mae, 2)))
}
if (abs(avg_model_bias) > 2) {
  alerts <- c(alerts, paste("⚠️  Model bias exceeds 2 points:", round(avg_model_bias, 2)))
}

if (length(alerts) > 0) {
  cat("\n=== PERFORMANCE ALERTS ===\n")
  for (alert in alerts) {
    cat(paste(alert, "\n"))
  }
}

cat("\n✓ Validation complete\n")
