# Investigate Spread Prediction Math
# This script examines the predictions and adjustments in detail

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

cat("=== INVESTIGATING SPREAD PREDICTIONS ===\n\n")

# Load the features data to see what went into predictions
features_data <- readRDS("data/features_data.rds")

# Load models to see coefficients
models <- readRDS("models/nfl_models.rds")

cat("Spread Model Coefficients:\n")
print(coef(models$spread))
cat("\n")

# Load predictions
base_preds <- read.csv("data/predictions/base_predictions.csv", stringsAsFactors = FALSE)
final_preds <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

cat("=== BASE PREDICTIONS ===\n")
print(base_preds %>% select(away_team, home_team, predicted_spread, predicted_total))

cat("\n=== CHECKING SPECIFIC GAMES ===\n\n")

# Function to examine a specific game
examine_game <- function(away, home) {
  cat(paste("--- ", away, "@", home, "---\n"))
  
  # Get base prediction
  base <- base_preds %>% filter(away_team == away, home_team == home)
  final <- final_preds %>% filter(away_team == away, home_team == home)
  
  if (nrow(base) == 0) {
    cat("Game not found in base predictions\n\n")
    return()
  }
  
  cat(paste("Base spread:", base$predicted_spread, "\n"))
  cat(paste("Final spread:", final$predicted_spread, "\n"))
  cat(paste("Adjustment:", final$predicted_spread - base$predicted_spread, "\n\n"))
  
  # Get latest stats for both teams
  home_stats <- features_data %>%
    filter(home_team == home) %>%
    arrange(desc(gameday)) %>%
    slice(1)
  
  away_stats <- features_data %>%
    filter(away_team == away) %>%
    arrange(desc(gameday)) %>%
    slice(1)
  
  if (nrow(home_stats) == 0) {
    home_stats <- features_data %>%
      filter(away_team == home) %>%
      arrange(desc(gameday)) %>%
      slice(1)
  }
  
  if (nrow(away_stats) == 0) {
    away_stats <- features_data %>%
      filter(home_team == away) %>%
      arrange(desc(gameday)) %>%
      slice(1)
  }
  
  cat("Home Team Latest Stats:\n")
  cat(paste("  Avg Points:", round(home_stats$home_avg_pts, 1), "\n"))
  cat(paste("  Avg Points Allowed:", round(home_stats$home_avg_pts_allowed, 1), "\n"))
  cat(paste("  Off EPA:", round(home_stats$home_off_epa, 3), "\n"))
  cat(paste("  Def EPA:", round(home_stats$home_def_epa, 3), "\n"))
  cat(paste("  Elo:", round(home_stats$home_elo_pre, 0), "\n\n"))
  
  cat("Away Team Latest Stats:\n")
  cat(paste("  Avg Points:", round(away_stats$away_avg_pts, 1), "\n"))
  cat(paste("  Avg Points Allowed:", round(away_stats$away_avg_pts_allowed, 1), "\n"))
  cat(paste("  Off EPA:", round(away_stats$away_off_epa, 3), "\n"))
  cat(paste("  Def EPA:", round(away_stats$away_def_epa, 3), "\n"))
  cat(paste("  Elo:", round(away_stats$away_elo_pre, 0), "\n\n"))
  
  # Calculate what the model would predict
  home_off_epa <- home_stats$home_off_epa
  away_off_epa <- away_stats$away_off_epa
  
  cat("Key Model Inputs:\n")
  cat(paste("  Home Off EPA:", round(home_off_epa, 3), "× 65.41 =", round(home_off_epa * 65.41, 1), "\n"))
  cat(paste("  Away Off EPA:", round(away_off_epa, 3), "× -63.16 =", round(away_off_epa * -63.16, 1), "\n"))
  cat(paste("  Combined EPA contribution:", round(home_off_epa * 65.41 + away_off_epa * -63.16, 1), "\n\n"))
}

# Examine the questionable games
examine_game("MIN", "CLE")
examine_game("HOU", "BAL")
examine_game("MIA", "CAR")

cat("\n=== SUMMARY STATISTICS ===\n")
cat(paste("Mean absolute base spread:", round(mean(abs(base_preds$predicted_spread)), 1), "\n"))
cat(paste("Max absolute base spread:", round(max(abs(base_preds$predicted_spread)), 1), "\n"))
cat(paste("Number of spreads > 20 points:", sum(abs(base_preds$predicted_spread) > 20), "\n"))

cat("\n=== TRAINING DATA SPREAD RANGE ===\n")
train_spreads <- features_data$home_score - features_data$away_score
cat(paste("Historical spread range:", round(min(train_spreads, na.rm = TRUE), 1), "to", round(max(train_spreads, na.rm = TRUE), 1), "\n"))
cat(paste("Mean absolute spread:", round(mean(abs(train_spreads), na.rm = TRUE), 1), "\n"))
cat(paste("95th percentile spread:", round(quantile(abs(train_spreads), 0.95, na.rm = TRUE), 1), "\n"))