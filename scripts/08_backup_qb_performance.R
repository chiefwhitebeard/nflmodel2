# NFL Predictions Model - Backup QB Historical Performance
# This script uses actual backup QB performance instead of generic weights

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(lubridate)
})

cat("Calculating backup QB historical performance...\n")

current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

seasons_to_load <- (current_season - 2):current_season

cat(paste("  Loading play-by-play data from", min(seasons_to_load), "to", max(seasons_to_load), "...\n"))

pbp_list <- list()
for (season in seasons_to_load) {
  pbp_list[[as.character(season)]] <- load_pbp(seasons = season)
}
pbp_all <- bind_rows(pbp_list)

qb_performance <- pbp_all %>%
  filter(!is.na(passer_player_name), !is.na(epa), pass == 1) %>%
  group_by(passer_player_name, passer_player_id) %>%
  summarise(
    pass_attempts = n(),
    epa_per_play = mean(epa, na.rm = TRUE),
    success_rate = mean(success, na.rm = TRUE),
    games_played = n_distinct(game_id),
    .groups = "drop"
  ) %>%
  filter(pass_attempts >= 50)

cat(paste("✓ Calculated performance for", nrow(qb_performance), "QBs\n"))

current_rosters <- load_rosters(seasons = current_season)

team_qbs <- current_rosters %>%
  filter(position == "QB") %>%
  select(team = team, full_name, gsis_id) %>%
  distinct()

team_qb_performance <- team_qbs %>%
  left_join(
    qb_performance,
    by = c("gsis_id" = "passer_player_id")
  ) %>%
  mutate(
    epa_per_play = ifelse(is.na(epa_per_play), 0, epa_per_play),
    has_history = !is.na(pass_attempts)
  )

cat(paste("✓ Mapped QB performance to", length(unique(team_qb_performance$team)), "teams\n"))

# Get current season usage to identify actual starters (not career totals)
cat("  Checking current season usage...\n")
current_season_pbp <- load_pbp(seasons = current_season)

current_season_usage <- current_season_pbp %>%
  filter(!is.na(passer_player_name)) %>%
  group_by(posteam, passer_player_id) %>%
  summarise(current_season_attempts = n(), .groups = "drop")

team_qb_performance <- team_qb_performance %>%
  left_join(current_season_usage, by = c("team" = "posteam", "gsis_id" = "passer_player_id")) %>%
  mutate(current_season_attempts = coalesce(current_season_attempts, 0))

# Load depth charts from nflreadr (replaces broken ESPN API)
cat("  Loading depth charts from nflreadr...\n")
depth_charts <- load_depth_charts(seasons = current_season)

# Get most recent depth chart for each team/position
latest_depth <- depth_charts %>%
  group_by(team, pos_abb) %>%
  filter(dt == max(dt)) %>%  # Most recent date only
  ungroup() %>%
  distinct(team, gsis_id, pos_abb, .keep_all = TRUE)

# Map depth chart positions to QB performance data
team_qb_performance <- team_qb_performance %>%
  left_join(
    latest_depth %>% 
      filter(pos_abb == "QB") %>%
      select(gsis_id, pos_rank),
    by = "gsis_id"
  ) %>%
  mutate(
    depth_chart_position = coalesce(as.numeric(pos_rank), 99)
  )

league_avg_epa <- mean(qb_performance$epa_per_play, na.rm = TRUE)
cat(paste("  League average QB EPA per play:", round(league_avg_epa, 3), "\n"))

saveRDS(team_qb_performance, "data/qb_performance.rds")
cat("✓ Saved QB performance database to data/qb_performance.rds\n")

cat("\n=== Top QBs by EPA/play (min 50 attempts) ===\n")
top_qbs <- qb_performance %>%
  arrange(desc(epa_per_play)) %>%
  head(10) %>%
  select(passer_player_name, epa_per_play, pass_attempts, games_played)
print(top_qbs)

cat("\n✓ Backup QB performance module ready\n")