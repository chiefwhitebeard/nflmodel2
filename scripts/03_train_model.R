# NFL Predictions Model - Enhanced Model Training Script
# This script trains prediction models using advanced EPA-based features

suppressPackageStartupMessages({
  library(dplyr)
  library(glmnet)
})

cat("Training enhanced NFL prediction models...\n")

# Load features
features_data <- readRDS("data/features_data.rds")

# Convert gameday to Date class
features_data$gameday <- as.Date(features_data$gameday)

# Remove rows with NA in critical columns
cat("Cleaning data...\n")
cat(paste("  Initial rows:", nrow(features_data), "\n"))

# Check for NAs in key predictors
predictors <- c("elo_diff", "home_avg_pts", "away_avg_pts", 
                "home_avg_pts_allowed", "away_avg_pts_allowed",
                "home_win_pct", "away_win_pct", 
                "home_rest", "away_rest", "rest_diff",
                "home_recent_form", "away_recent_form",
                "home_off_epa", "away_off_epa",
                "home_def_epa", "away_def_epa",
                "home_success_rate", "away_success_rate",
                "is_divisional", "home_win")

# Debug: Show which columns exist
cat("\nChecking which predictor columns exist:\n")
for (pred in predictors) {
  exists <- pred %in% names(features_data)
  if (exists) {
    na_count <- sum(is.na(features_data[[pred]]))
    cat(paste("  ", pred, "- EXISTS,", na_count, "NAs out of", nrow(features_data), "\n"))
  } else {
    cat(paste("  ", pred, "- MISSING!\n"))
  }
}

# Only use predictors that exist
existing_predictors <- predictors[predictors %in% names(features_data)]

# Remove rows with any NA in existing predictors
# Convert to data frame to avoid data.table issues
features_data <- as.data.frame(features_data)
features_data_clean <- features_data[complete.cases(features_data[, existing_predictors]), ]

cat(paste("  Rows after removing NAs:", nrow(features_data_clean), "\n"))
cat(paste("  Rows removed:", nrow(features_data) - nrow(features_data_clean), "\n"))

# Prepare training data (exclude most recent 4 weeks for validation)
max_date <- max(features_data_clean$gameday)
train_cutoff <- max_date - 28

train_data <- features_data_clean[features_data_clean$gameday < train_cutoff, ]
test_data <- features_data_clean[features_data_clean$gameday >= train_cutoff, ]

cat(paste("\nTraining games:", nrow(train_data), "\n"))
cat(paste("Testing games:", nrow(test_data), "\n"))

# Model 1: Enhanced Winner Prediction (Classification)
cat("\n1. Training enhanced game winner model...\n")

winner_model <- glm(
  home_win ~ elo_diff + 
    home_avg_pts + away_avg_pts + 
    home_avg_pts_allowed + away_avg_pts_allowed +
    home_win_pct + away_win_pct + 
    home_rest + away_rest + rest_diff +
    home_recent_form + away_recent_form +
    home_off_epa + away_off_epa +
    home_success_rate + away_success_rate +
    is_divisional,
  data = train_data,
  family = binomial()
)

# Evaluate on test set
test_pred_prob <- predict(winner_model, newdata = test_data, type = "response")
test_pred_winner <- ifelse(test_pred_prob > 0.5, 1, 0)
accuracy <- mean(test_pred_winner == test_data$home_win, na.rm = TRUE)

cat(paste("  Winner prediction accuracy:", round(accuracy * 100, 1), "%\n"))

# Model 2: Enhanced Point Spread Prediction (Regression)
cat("\n2. Training enhanced point spread model...\n")

train_data$point_diff <- train_data$home_score - train_data$away_score

spread_model <- lm(
  point_diff ~ elo_diff + 
    home_avg_pts + away_avg_pts +
    home_avg_pts_allowed + away_avg_pts_allowed +
    home_recent_form + away_recent_form +
    home_off_epa + away_off_epa +
    home_success_rate + away_success_rate +
    rest_diff +
    is_divisional,
  data = train_data
)

# Evaluate spread predictions
test_data$actual_diff <- test_data$home_score - test_data$away_score
test_pred_spread <- predict(spread_model, newdata = test_data)
mae <- mean(abs(test_pred_spread - test_data$actual_diff), na.rm = TRUE)
r_squared <- summary(spread_model)$r.squared

cat(paste("  Mean Absolute Error (points):", round(mae, 2), "\n"))
cat(paste("  R-squared:", round(r_squared, 3), "\n"))

# Model 3: Enhanced Total Points (Over/Under)
cat("\n3. Training enhanced total points model...\n")

train_data$total_points <- train_data$home_score + train_data$away_score

total_model <- lm(
  total_points ~ home_avg_pts + away_avg_pts + 
    home_avg_pts_allowed + away_avg_pts_allowed +
    home_off_epa + away_off_epa +
    home_success_rate + away_success_rate +
    is_divisional,
  data = train_data
)

# Evaluate total predictions
test_data$actual_total <- test_data$home_score + test_data$away_score
test_pred_total <- predict(total_model, newdata = test_data)
total_mae <- mean(abs(test_pred_total - test_data$actual_total), na.rm = TRUE)
total_r_squared <- summary(total_model)$r.squared

cat(paste("  Mean Absolute Error (points):", round(total_mae, 2), "\n"))
cat(paste("  R-squared:", round(total_r_squared, 3), "\n"))

# Save all models with metadata
models <- list(
  winner = winner_model,
  spread = spread_model,
  total = total_model,
  train_date = Sys.Date(),
  accuracy = accuracy,
  spread_mae = mae,
  spread_r_squared = r_squared,
  total_mae = total_mae,
  total_r_squared = total_r_squared
)

saveRDS(models, "models/nfl_models.rds")
cat("\n✓ All enhanced models saved to models/nfl_models.rds\n")

# Save model performance summary
performance <- data.frame(
  model = c("Winner", "Spread", "Spread", "Total", "Total"),
  metric = c("Accuracy", "MAE", "R-squared", "MAE", "R-squared"),
  value = c(accuracy, mae, r_squared, total_mae, total_r_squared),
  train_date = Sys.Date(),
  stringsAsFactors = FALSE
)

saveRDS(performance, "models/model_performance.rds")
cat("✓ Performance metrics saved\n")

cat("\n=== Enhanced Model Training Complete ===\n")
print(performance)

# Display spread model summary for R-squared verification
cat("\n=== Spread Model Summary ===\n")
print(summary(spread_model))