# NFL Predictions Model - Enhanced Feature Engineering Script
# This script calculates advanced features including EPA metrics for better predictions

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(zoo)
})

cat("Calculating enhanced team features...\n")

# Load raw game data
all_games <- readRDS("data/raw_game_data.rds")

# Load play-by-play data for EPA calculations
cat("  Loading play-by-play data for EPA metrics...\n")
seasons <- unique(all_games$season)
pbp_list <- list()
for (season in seasons) {
  cat(paste("    Loading", season, "play-by-play...\n"))
  pbp_list[[as.character(season)]] <- load_pbp(seasons = season)
}
pbp_all <- bind_rows(pbp_list)

# Calculate EPA-based team metrics by game
cat("  Calculating EPA metrics per game...\n")
team_epa_by_game <- pbp_all %>%
  filter(!is.na(posteam), !is.na(epa)) %>%
  group_by(season, week, game_id, posteam) %>%
  summarise(
    off_epa_per_play = mean(epa, na.rm = TRUE),
    off_success_rate = mean(success, na.rm = TRUE),
    off_explosive_rate = mean(epa > 0.5, na.rm = TRUE),
    pass_epa = mean(epa[pass == 1], na.rm = TRUE),
    rush_epa = mean(epa[rush == 1], na.rm = TRUE),
    pace = n(),  # Total plays per game (offensive pace)
    .groups = "drop"
  )

# Calculate defensive EPA (when team is on defense)
team_def_by_game <- pbp_all %>%
  filter(!is.na(defteam), !is.na(epa)) %>%
  group_by(season, week, game_id, defteam) %>%
  summarise(
    def_epa_per_play = mean(epa, na.rm = TRUE),
    def_success_rate_allowed = mean(success, na.rm = TRUE),
    .groups = "drop"
  )

# Calculate Elo ratings
cat("  Calculating Elo ratings...\n")
calculate_elo <- function(games, k = 20, initial_elo = 1500) {
  elo_ratings <- list()
  teams <- unique(c(games$home_team, games$away_team))
  
  for (team in teams) {
    elo_ratings[[team]] <- initial_elo
  }
  
  games <- games[order(games$gameday), ]
  
  elo_history <- data.frame(
    game_id = character(),
    home_team = character(),
    away_team = character(),
    home_elo_pre = numeric(),
    away_elo_pre = numeric(),
    home_elo_post = numeric(),
    away_elo_post = numeric(),
    stringsAsFactors = FALSE
  )
  
  for (i in 1:nrow(games)) {
    game <- games[i, ]
    
    home_elo <- elo_ratings[[game$home_team]]
    away_elo <- elo_ratings[[game$away_team]]
    
    home_expected <- 1 / (1 + 10^((away_elo - home_elo) / 400))
    
    if (game$home_score > game$away_score) {
      home_actual <- 1
    } else if (game$home_score < game$away_score) {
      home_actual <- 0
    } else {
      home_actual <- 0.5
    }
    
    home_elo_new <- home_elo + k * (home_actual - home_expected)
    away_elo_new <- away_elo + k * ((1 - home_actual) - (1 - home_expected))
    
    elo_history <- rbind(elo_history, data.frame(
      game_id = game$game_id,
      home_team = game$home_team,
      away_team = game$away_team,
      home_elo_pre = home_elo,
      away_elo_pre = away_elo,
      home_elo_post = home_elo_new,
      away_elo_post = away_elo_new,
      stringsAsFactors = FALSE
    ))
    
    elo_ratings[[game$home_team]] <- home_elo_new
    elo_ratings[[game$away_team]] <- away_elo_new
  }
  
  return(elo_history)
}

elo_data <- calculate_elo(all_games)
games_with_elo <- merge(all_games, elo_data, by = c("game_id", "home_team", "away_team"))

# Merge per-game EPA data into games_with_elo for rolling calculation
games_with_elo <- games_with_elo %>%
  left_join(team_epa_by_game %>%
              select(game_id, team = posteam, off_epa_game = off_epa_per_play,
                     success_rate_game = off_success_rate, explosive_rate_game = off_explosive_rate,
                     pace_game = pace),
            by = c("game_id", "home_team" = "team")) %>%
  rename(home_off_epa_game = off_epa_game, home_success_rate_game = success_rate_game,
         home_explosive_rate_game = explosive_rate_game, home_pace_game = pace_game) %>%
  left_join(team_epa_by_game %>%
              select(game_id, team = posteam, off_epa_game = off_epa_per_play,
                     success_rate_game = off_success_rate, explosive_rate_game = off_explosive_rate,
                     pace_game = pace),
            by = c("game_id", "away_team" = "team")) %>%
  rename(away_off_epa_game = off_epa_game, away_success_rate_game = success_rate_game,
         away_explosive_rate_game = explosive_rate_game, away_pace_game = pace_game) %>%
  left_join(team_def_by_game %>%
              select(game_id, team = defteam, def_epa_game = def_epa_per_play),
            by = c("game_id", "home_team" = "team")) %>%
  rename(home_def_epa_game = def_epa_game) %>%
  left_join(team_def_by_game %>%
              select(game_id, team = defteam, def_epa_game = def_epa_per_play),
            by = c("game_id", "away_team" = "team")) %>%
  rename(away_def_epa_game = def_epa_game)

# Calculate rolling statistics including EPA metrics
cat("  Calculating rolling team statistics with EPA metrics...\n")

calculate_team_stats <- function(games, team, n_games = 10) {
  team_games <- games[games$home_team == team | games$away_team == team, ]
  team_games <- team_games[order(team_games$gameday), ]

  team_games$is_home <- team_games$home_team == team
  team_games$points_for <- ifelse(team_games$is_home, team_games$home_score, team_games$away_score)
  team_games$points_against <- ifelse(team_games$is_home, team_games$away_score, team_games$home_score)
  team_games$win <- ifelse(team_games$is_home,
                           team_games$home_score > team_games$away_score,
                           team_games$away_score > team_games$home_score)
  team_games$current_elo <- ifelse(team_games$is_home, team_games$home_elo_post, team_games$away_elo_post)

  # Extract EPA metrics for this team (from either home or away perspective)
  team_games$off_epa_game <- ifelse(team_games$is_home,
                                     team_games$home_off_epa_game,
                                     team_games$away_off_epa_game)
  team_games$def_epa_game <- ifelse(team_games$is_home,
                                     team_games$home_def_epa_game,
                                     team_games$away_def_epa_game)
  team_games$success_rate_game <- ifelse(team_games$is_home,
                                          team_games$home_success_rate_game,
                                          team_games$away_success_rate_game)
  team_games$explosive_rate_game <- ifelse(team_games$is_home,
                                            team_games$home_explosive_rate_game,
                                            team_games$away_explosive_rate_game)
  team_games$pace_game <- ifelse(team_games$is_home,
                                  team_games$home_pace_game,
                                  team_games$away_pace_game)

  # Calculate rolling averages (shift by 1 to avoid look-ahead bias)
  team_games$avg_points_for <- rollmean(c(rep(NA, 1), head(team_games$points_for, -1)),
                                        k = n_games, fill = NA, align = "right")
  team_games$avg_points_against <- rollmean(c(rep(NA, 1), head(team_games$points_against, -1)),
                                            k = n_games, fill = NA, align = "right")
  team_games$win_pct <- rollmean(c(rep(NA, 1), head(as.numeric(team_games$win), -1)),
                                 k = n_games, fill = NA, align = "right")

  # Rolling EPA averages (shift by 1 to avoid look-ahead bias)
  team_games$off_epa_avg <- rollmean(c(rep(NA, 1), head(team_games$off_epa_game, -1)),
                                      k = n_games, fill = NA, align = "right")
  team_games$def_epa_avg <- rollmean(c(rep(NA, 1), head(team_games$def_epa_game, -1)),
                                      k = n_games, fill = NA, align = "right")
  team_games$success_rate_avg <- rollmean(c(rep(NA, 1), head(team_games$success_rate_game, -1)),
                                           k = n_games, fill = NA, align = "right")
  team_games$explosive_rate_avg <- rollmean(c(rep(NA, 1), head(team_games$explosive_rate_game, -1)),
                                             k = n_games, fill = NA, align = "right")
  team_games$pace_avg <- rollmean(c(rep(NA, 1), head(team_games$pace_game, -1)),
                                   k = n_games, fill = NA, align = "right")

  # Recent form (last 3 games weighted)
  team_games$recent_form <- rollapply(c(rep(NA, 1), head(as.numeric(team_games$win), -1)),
                                      width = 3, FUN = function(x) {
                                        if(length(x[!is.na(x)]) == 0) return(NA)
                                        if(length(x[!is.na(x)]) < 3) {
                                          # For partial windows, use equal weights
                                          return(mean(x, na.rm = TRUE))
                                        }
                                        weighted.mean(x, c(1, 1.5, 2), na.rm = TRUE)
                                      },
                                      fill = NA, align = "right", partial = TRUE)

  team_games$elo_rating <- c(NA, head(team_games$current_elo, -1))

  return(team_games)
}

# Get all unique teams
all_teams <- unique(c(games_with_elo$home_team, games_with_elo$away_team))

# Calculate stats for all teams
team_stats_list <- lapply(all_teams, function(team) {
  calculate_team_stats(games_with_elo, team)
})
team_stats <- do.call(rbind, team_stats_list)

# Create final feature dataset with rolling EPA averages (no per-game EPA merge needed)
home_stats <- team_stats[team_stats$is_home == TRUE,
                         c("game_id", "avg_points_for", "avg_points_against", "win_pct",
                           "elo_rating", "recent_form", "off_epa_avg", "def_epa_avg",
                           "success_rate_avg", "explosive_rate_avg", "pace_avg")]
names(home_stats) <- c("game_id", "home_avg_pts", "home_avg_pts_allowed", "home_win_pct",
                       "home_elo", "home_recent_form", "home_off_epa", "home_def_epa",
                       "home_success_rate", "home_explosive_rate", "home_pace")

away_stats <- team_stats[team_stats$is_home == FALSE,
                         c("game_id", "avg_points_for", "avg_points_against", "win_pct",
                           "elo_rating", "recent_form", "off_epa_avg", "def_epa_avg",
                           "success_rate_avg", "explosive_rate_avg", "pace_avg")]
names(away_stats) <- c("game_id", "away_avg_pts", "away_avg_pts_allowed", "away_win_pct",
                       "away_elo", "away_recent_form", "away_off_epa", "away_def_epa",
                       "away_success_rate", "away_explosive_rate", "away_pace")

features_data <- merge(games_with_elo, home_stats, by = "game_id", all.x = TRUE)
features_data <- merge(features_data, away_stats, by = "game_id", all.x = TRUE)

# Add derived features
features_data$elo_diff <- features_data$home_elo_pre - features_data$away_elo_pre
features_data$home_win <- as.numeric(features_data$home_score > features_data$away_score)
features_data$epa_diff <- features_data$home_off_epa - features_data$away_off_epa
features_data$def_epa_diff <- features_data$away_def_epa - features_data$home_def_epa

# Calculate rest differential (days since last game)
# Sort by team and date to calculate rest for each team
features_data <- features_data %>%
  arrange(gameday)

# Initialize rest columns
features_data$home_rest <- NA
features_data$away_rest <- NA

# Calculate rest for each game
for (i in 1:nrow(features_data)) {
  current_game <- features_data[i, ]
  home_team <- current_game$home_team
  away_team <- current_game$away_team
  current_date <- current_game$gameday
  
  # Find home team's previous game
  home_prev <- features_data %>%
    filter((home_team == !!home_team | away_team == !!home_team) & gameday < !!current_date) %>%
    arrange(desc(gameday)) %>%
    slice(1)
  
  if (nrow(home_prev) > 0) {
    features_data$home_rest[i] <- as.numeric(difftime(current_date, home_prev$gameday, units = "days"))
  } else {
    features_data$home_rest[i] <- 7  # Default for first game
  }
  
  # Find away team's previous game
  away_prev <- features_data %>%
    filter((home_team == !!away_team | away_team == !!away_team) & gameday < !!current_date) %>%
    arrange(desc(gameday)) %>%
    slice(1)
  
  if (nrow(away_prev) > 0) {
    features_data$away_rest[i] <- as.numeric(difftime(current_date, away_prev$gameday, units = "days"))
  } else {
    features_data$away_rest[i] <- 7  # Default for first game
  }
}

# Add rest differential
features_data$rest_diff <- features_data$home_rest - features_data$away_rest

# Add divisional game indicator
divisions <- data.frame(
  team = c("BUF", "MIA", "NE", "NYJ", "BAL", "CIN", "CLE", "PIT", 
           "HOU", "IND", "JAX", "TEN", "DEN", "KC", "LV", "LAC",
           "DAL", "NYG", "PHI", "WAS", "CHI", "DET", "GB", "MIN",
           "ATL", "CAR", "NO", "TB", "ARI", "LA", "SF", "SEA"),
  division = c(rep("AFC East", 4), rep("AFC North", 4), rep("AFC South", 4), rep("AFC West", 4),
               rep("NFC East", 4), rep("NFC North", 4), rep("NFC South", 4), rep("NFC West", 4)),
  stringsAsFactors = FALSE
)

features_data <- features_data %>%
  left_join(divisions, by = c("home_team" = "team")) %>%
  rename(home_division = division) %>%
  left_join(divisions, by = c("away_team" = "team")) %>%
  rename(away_division = division) %>%
  mutate(is_divisional = as.numeric(home_division == away_division))

# Remove games without complete features
features_data <- features_data[!is.na(features_data$home_elo) & !is.na(features_data$away_elo), ]

cat(paste("✓ Calculated enhanced features for", nrow(features_data), "games\n"))

# Save features
saveRDS(features_data, "data/features_data.rds")
cat("✓ Saved enhanced features to data/features_data.rds\n")

cat("\nEnhanced Feature Summary:\n")
cat(paste("  Games with complete features:", nrow(features_data), "\n"))
cat(paste("  Teams:", length(unique(c(features_data$home_team, features_data$away_team))), "\n"))
cat("  New features: EPA metrics, recent form, divisional indicator, rest differential\n")