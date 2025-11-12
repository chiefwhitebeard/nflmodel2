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

# Find most recent archived prediction file with ALL games completed
prediction_files <- list.files("data/predictions", pattern = "^predictions_primary_\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE)

if (length(prediction_files) == 0) {
  cat("No archived prediction files found. Nothing to validate.\n")
  quit(save = "no", status = 0)
}

# Load actual results for current season
current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

schedule <- load_schedules(seasons = current_season)
schedule$gameday <- as.Date(schedule$gameday)

# Sort prediction files from newest to oldest and find first with all games complete
prediction_files_sorted <- prediction_files[order(prediction_files, decreasing = TRUE)]

latest_archive <- NULL
predictions <- NULL

for (pred_file in prediction_files_sorted) {
  cat(paste("Checking:", basename(pred_file), "... "))

  temp_predictions <- read.csv(pred_file, stringsAsFactors = FALSE)
  temp_predictions$game_date <- as.Date(temp_predictions$game_date)

  # Match to actual results
  temp_results <- temp_predictions %>%
    left_join(
      schedule %>% select(gameday, home_team, away_team, home_score, away_score, result),
      by = c("game_date" = "gameday", "home_team", "away_team")
    )

  # Check if ALL games are complete
  total_games <- nrow(temp_predictions)
  completed_games <- sum(!is.na(temp_results$home_score))

  cat(paste(completed_games, "/", total_games, "games complete"))

  if (completed_games == total_games && total_games > 0) {
    cat(" ✓ Using this file\n")
    latest_archive <- pred_file
    predictions <- temp_predictions
    break
  } else {
    cat("\n")
  }
}

if (is.null(latest_archive)) {
  cat("\nNo prediction files found with all games completed.\n")
  quit(save = "no", status = 0)
}

cat(paste("\nValidating:", basename(latest_archive), "\n"))

# Match predictions to actual results (we know all games are complete)
results <- predictions %>%
  left_join(
    schedule %>% select(gameday, home_team, away_team, home_score, away_score, result),
    by = c("game_date" = "gameday", "home_team", "away_team")
  ) %>%
  filter(!is.na(home_score))  # Only completed games

cat(paste("Found", nrow(results), "completed games to validate\n"))

# Predictions already have final_spread and final_home_win_probability columns
# Just use them directly

# Calculate validation metrics
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

# Simple record summary
wins <- sum(results$winner_correct)
losses <- sum(!results$winner_correct)
total_games <- nrow(results)

cat(paste("Record:", wins, "-", losses, "out of", total_games, "games\n"))
cat(paste("Winner Accuracy:", round(winner_accuracy * 100, 1), "%\n"))
cat(paste("Spread MAE:", round(spread_mae, 2), "points\n"))
cat(paste("Total MAE:", round(total_mae, 2), "points\n"))
cat(paste("Model Bias:", round(avg_model_bias, 2), "points (+ favors home)\n"))

# Breakdown by adjustment stage
if ("base_spread" %in% names(results) && "spread_after_injuries" %in% names(results)) {
  cat("\n=== Adjustment Impact Analysis ===\n")

  base_mae <- mean(abs(results$base_spread - results$actual_spread), na.rm = TRUE)
  injury_mae <- mean(abs(results$spread_after_injuries - results$actual_spread), na.rm = TRUE)
  final_mae <- mean(abs(results$final_spread - results$actual_spread), na.rm = TRUE)

  cat(paste("Base Model MAE:", round(base_mae, 2), "points\n"))
  cat(paste("After Injuries MAE:", round(injury_mae, 2), "points (",
            ifelse(injury_mae < base_mae, "✓ improved", "⚠ worse"), ")\n"))
  cat(paste("Final (with Weather) MAE:", round(final_mae, 2), "points (",
            ifelse(final_mae < injury_mae, "✓ improved", "⚠ worse"), ")\n"))
}

# Save detailed results
validation_date <- Sys.Date()
detail_file <- paste0("data/validation/validation_detail_", validation_date, ".csv")
write.csv(results, detail_file, row.names = FALSE)
cat(paste("\n✓ Detailed results saved to", detail_file, "\n"))

# Append to accuracy log
log_entry <- data.frame(
  validation_date = as.character(validation_date),  # Format as string to prevent numeric serialization
  prediction_date = unique(predictions$prediction_date)[1],
  prediction_file = basename(latest_archive),
  games_validated = nrow(results),
  games_incomplete = 0,  # All games in results are completed by definition
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
