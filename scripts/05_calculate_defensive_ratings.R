# NFL Predictions Model - Calculate Defensive Ratings
# This script calculates defensive quality by position group for opponent adjustments

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(lubridate)
})

cat("Calculating defensive quality ratings...\n")

# Get current season
current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

cat(paste("  Loading", current_season, "play-by-play data...\n"))

# Load play-by-play data for defensive EPA calculations
pbp <- load_pbp(seasons = current_season)

# Calculate defensive EPA allowed by position group
cat("  Calculating defensive EPA by team...\n")

# Pass defense quality (EPA allowed per pass attempt)
pass_defense <- pbp %>%
  filter(!is.na(defteam), !is.na(epa), pass == 1) %>%
  group_by(defteam) %>%
  summarise(
    pass_epa_allowed = mean(epa, na.rm = TRUE),
    pass_attempts_faced = n(),
    .groups = "drop"
  ) %>%
  mutate(
    pass_defense_rank = rank(pass_epa_allowed),
    pass_defense_multiplier = 1 + (pass_defense_rank - 16.5) / 32
  )

# Rush defense quality (EPA allowed per rush)
rush_defense <- pbp %>%
  filter(!is.na(defteam), !is.na(epa), rush == 1) %>%
  group_by(defteam) %>%
  summarise(
    rush_epa_allowed = mean(epa, na.rm = TRUE),
    rush_attempts_faced = n(),
    .groups = "drop"
  ) %>%
  mutate(
    rush_defense_rank = rank(rush_epa_allowed),
    rush_defense_multiplier = 1 + (rush_defense_rank - 16.5) / 32
  )

# Combine defensive metrics
defense_ratings <- pass_defense %>%
  left_join(rush_defense %>% select(defteam, rush_epa_allowed, rush_defense_multiplier),
            by = "defteam")

cat(paste("✓ Computed defensive ratings for", nrow(defense_ratings), "teams\n"))

# Save defensive ratings
saveRDS(defense_ratings, "data/defense_ratings.rds")
cat("✓ Saved to data/defense_ratings.rds\n")

# Show top/bottom defenses
cat("\n=== Best Pass Defenses (lowest EPA allowed) ===\n")
best_pass <- defense_ratings %>%
  arrange(pass_epa_allowed) %>%
  head(5) %>%
  select(defteam, pass_epa_allowed, pass_defense_multiplier)
print(best_pass)

cat("\n=== Worst Pass Defenses (highest EPA allowed) ===\n")
worst_pass <- defense_ratings %>%
  arrange(desc(pass_epa_allowed)) %>%
  head(5) %>%
  select(defteam, pass_epa_allowed, pass_defense_multiplier)
print(worst_pass)