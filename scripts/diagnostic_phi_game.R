# Diagnostic: Trace PHI game prediction calculation

library(dplyr)
library(nflreadr)

cat("=== DIAGNOSTIC: DEN @ PHI PREDICTION ===\n\n")

# 1. Load model coefficients
models <- readRDS("models/nfl_models.rds")
cat("Spread Model Coefficients:\n")
coefs <- coef(models$spread)
print(coefs)

# 2. Load current season EPA
cat("\n=== Season EPA Values ===\n")
current_pbp <- load_pbp(seasons = 2025)
season_epa <- current_pbp %>%
  filter(!is.na(posteam), !is.na(epa)) %>%
  group_by(posteam) %>%
  summarise(
    off_epa = mean(epa, na.rm = TRUE),
    success_rate = mean(success, na.rm = TRUE)
  )

den_epa <- season_epa %>% filter(posteam == "DEN")
phi_epa <- season_epa %>% filter(posteam == "PHI")

cat("Denver EPA:", den_epa$off_epa, "\n")
cat("Philadelphia EPA:", phi_epa$off_epa, "\n")
cat("EPA difference (PHI - DEN):", phi_epa$off_epa - den_epa$off_epa, "\n")

# 3. Load historical stats
features <- readRDS("data/features_data.rds")

den_stats <- features %>% filter(away_team == "DEN") %>% arrange(desc(gameday)) %>% slice(1)
phi_stats <- features %>% filter(home_team == "PHI") %>% arrange(desc(gameday)) %>% slice(1)

cat("\n=== Historical Stats ===\n")
cat("Denver (most recent as away):\n")
cat("  Avg pts:", den_stats$away_avg_pts, "\n")
cat("  Avg pts allowed:", den_stats$away_avg_pts_allowed, "\n")
cat("  Win pct:", den_stats$away_win_pct, "\n")
cat("  Elo:", den_stats$away_elo_pre, "\n")
cat("  Recent form:", den_stats$away_recent_form, "\n")

cat("\nPhiladelphia (most recent as home):\n")
cat("  Avg pts:", phi_stats$home_avg_pts, "\n")
cat("  Avg pts allowed:", phi_stats$home_avg_pts_allowed, "\n")
cat("  Win pct:", phi_stats$home_win_pct, "\n")
cat("  Elo:", phi_stats$home_elo_pre, "\n")
cat("  Recent form:", phi_stats$home_recent_form, "\n")

# 4. Calculate predicted spread step by step
cat("\n=== Spread Calculation (PHI perspective) ===\n")

intercept <- coefs["(Intercept)"]
elo_contribution <- coefs["elo_diff"] * (phi_stats$home_elo_pre - den_stats$away_elo_pre)
home_pts_contribution <- coefs["home_avg_pts"] * phi_stats$home_avg_pts
away_pts_contribution <- coefs["away_avg_pts"] * den_stats$away_avg_pts
home_allowed_contribution <- coefs["home_avg_pts_allowed"] * phi_stats$home_avg_pts_allowed
away_allowed_contribution <- coefs["away_avg_pts_allowed"] * den_stats$away_avg_pts_allowed
home_form_contribution <- coefs["home_recent_form"] * phi_stats$home_recent_form
away_form_contribution <- coefs["away_recent_form"] * den_stats$away_recent_form
home_epa_contribution <- coefs["home_off_epa"] * phi_epa$off_epa
away_epa_contribution <- coefs["away_off_epa"] * den_epa$off_epa
home_success_contribution <- coefs["home_success_rate"] * phi_epa$success_rate
away_success_contribution <- coefs["away_success_rate"] * den_epa$success_rate

total <- intercept + elo_contribution + home_pts_contribution + away_pts_contribution +
  home_allowed_contribution + away_allowed_contribution + home_form_contribution +
  away_form_contribution + home_epa_contribution + away_epa_contribution +
  home_success_contribution + away_success_contribution

cat("Intercept:", round(intercept, 2), "\n")
cat("Elo contribution:", round(elo_contribution, 2), "\n")
cat("EPA contribution:", round(home_epa_contribution + away_epa_contribution, 2), "\n")
cat("Pts avg contribution:", round(home_pts_contribution + away_pts_contribution, 2), "\n")
cat("\nTOTAL:", round(total, 2), "\n")