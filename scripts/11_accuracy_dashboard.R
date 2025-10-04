# NFL Predictions Model - Accuracy Dashboard
# Generates visualizations and statistics from validation log

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

cat("Generating accuracy dashboard...\n")

# Load accuracy log
log_file <- "data/validation/accuracy_log.csv"

if (!file.exists(log_file)) {
  cat("No validation log found. Run validation first.\n")
  quit(save = "no", status = 0)
}

log_data <- read.csv(log_file, stringsAsFactors = FALSE)
log_data$validation_date <- as.Date(log_data$validation_date)
log_data$prediction_date <- as.Date(log_data$prediction_date)

cat(paste("Loaded", nrow(log_data), "validation records\n"))

if (nrow(log_data) < 2) {
  cat("Need at least 2 validation records for meaningful dashboard.\n")
  cat("Current data:\n")
  print(log_data)
  quit(save = "no", status = 0)
}

# Summary statistics
cat("\n=== Overall Performance ===\n")
cat(paste("Total games validated:", sum(log_data$games_validated), "\n"))
cat(paste("Average winner accuracy:", round(mean(log_data$winner_accuracy) * 100, 1), "%\n"))
cat(paste("Average spread MAE:", round(mean(log_data$spread_mae), 2), "points\n"))
cat(paste("Average total MAE:", round(mean(log_data$total_mae), 2), "points\n"))
cat(paste("Average model bias:", round(mean(log_data$model_bias), 2), "points\n"))

# Rolling averages (last 4 weeks)
if (nrow(log_data) >= 4) {
  recent <- tail(log_data, 4)
  cat("\n=== Last 4 Weeks ===\n")
  cat(paste("Winner accuracy:", round(mean(recent$winner_accuracy) * 100, 1), "%\n"))
  cat(paste("Spread MAE:", round(mean(recent$spread_mae), 2), "points\n"))
  cat(paste("Total MAE:", round(mean(recent$total_mae), 2), "points\n"))
}

# Trend analysis
cat("\n=== Trends ===\n")
if (nrow(log_data) >= 3) {
  recent_3 <- tail(log_data, 3)
  older_3 <- head(log_data, min(3, nrow(log_data) - 3))
  
  if (nrow(older_3) > 0) {
    acc_trend <- mean(recent_3$winner_accuracy) - mean(older_3$winner_accuracy)
    spread_trend <- mean(recent_3$spread_mae) - mean(older_3$spread_mae)
    
    cat(paste("Winner accuracy trend:", ifelse(acc_trend > 0, "+", ""), 
              round(acc_trend * 100, 1), "percentage points\n"))
    cat(paste("Spread MAE trend:", ifelse(spread_trend > 0, "+", ""), 
              round(spread_trend, 2), "points\n"))
  }
}

# Create plots
cat("\n=== Generating plots ===\n")

# 1. Winner Accuracy Over Time
p1 <- ggplot(log_data, aes(x = validation_date, y = winner_accuracy * 100)) +
  geom_line(color = "steelblue", size = 1) +
  geom_point(color = "steelblue", size = 3) +
  geom_hline(yintercept = 60, linetype = "dashed", color = "red", alpha = 0.5) +
  geom_hline(yintercept = 68.8, linetype = "dashed", color = "darkgreen", alpha = 0.5) +
  labs(title = "Winner Prediction Accuracy Over Time",
       subtitle = "Green line = training accuracy (68.8%), Red line = minimum threshold (60%)",
       x = "Validation Date", y = "Accuracy (%)") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave("data/validation/plot_winner_accuracy.png", p1, width = 10, height = 6)
cat("✓ Saved winner accuracy plot\n")

# 2. Spread MAE Over Time
p2 <- ggplot(log_data, aes(x = validation_date, y = spread_mae)) +
  geom_line(color = "coral", size = 1) +
  geom_point(color = "coral", size = 3) +
  geom_hline(yintercept = 8.95, linetype = "dashed", color = "darkgreen", alpha = 0.5) +
  geom_hline(yintercept = 12, linetype = "dashed", color = "red", alpha = 0.5) +
  labs(title = "Spread Mean Absolute Error Over Time",
       subtitle = "Green line = training MAE (8.95), Red line = alert threshold (12)",
       x = "Validation Date", y = "MAE (points)") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave("data/validation/plot_spread_mae.png", p2, width = 10, height = 6)
cat("✓ Saved spread MAE plot\n")

# 3. Model Bias Over Time
p3 <- ggplot(log_data, aes(x = validation_date, y = model_bias)) +
  geom_line(color = "purple", size = 1) +
  geom_point(color = "purple", size = 3) +
  geom_hline(yintercept = 0, linetype = "solid", color = "gray", alpha = 0.5) +
  geom_hline(yintercept = 2, linetype = "dashed", color = "red", alpha = 0.5) +
  geom_hline(yintercept = -2, linetype = "dashed", color = "red", alpha = 0.5) +
  labs(title = "Model Bias Over Time",
       subtitle = "Positive = favors home team, Negative = favors away team",
       x = "Validation Date", y = "Bias (points)") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave("data/validation/plot_model_bias.png", p3, width = 10, height = 6)
cat("✓ Saved model bias plot\n")

# 4. Combined metrics
log_long <- log_data %>%
  select(validation_date, winner_accuracy, spread_mae, total_mae) %>%
  tidyr::pivot_longer(cols = c(winner_accuracy, spread_mae, total_mae),
                      names_to = "metric", values_to = "value")

# Normalize for plotting together
log_long <- log_long %>%
  mutate(
    normalized_value = case_when(
      metric == "winner_accuracy" ~ value * 100,
      metric == "spread_mae" ~ value,
      metric == "total_mae" ~ value
    ),
    metric_label = case_when(
      metric == "winner_accuracy" ~ "Winner Accuracy (%)",
      metric == "spread_mae" ~ "Spread MAE (pts)",
      metric == "total_mae" ~ "Total MAE (pts)"
    )
  )

p4 <- ggplot(log_long, aes(x = validation_date, y = normalized_value, color = metric_label)) +
  geom_line(size = 1) +
  geom_point(size = 2) +
  labs(title = "All Metrics Over Time",
       x = "Validation Date", y = "Value", color = "Metric") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave("data/validation/plot_combined_metrics.png", p4, width = 10, height = 6)
cat("✓ Saved combined metrics plot\n")

cat("\n✓ Dashboard complete\n")
cat("View plots in: data/validation/\n")