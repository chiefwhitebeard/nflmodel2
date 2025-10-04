# NFL Predictions Model - Weekly Predictions Script
# This script generates predictions for upcoming NFL games

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(lubridate)
})

cat("Generating NFL predictions for upcoming games...\n")

# Load trained models
models <- readRDS("models/nfl_models.rds")

# Function to calculate cover probability using spread uncertainty
calculate_cover_probability <- function(predicted_spread) {
  # NFL spread uncertainty (empirical observation: ~10 point standard deviation)
  sigma <- 10.0
  
  # Cover probability = P(actual spread >= predicted spread)
  # Using normal distribution centered on our prediction
  cover_prob <- pnorm(0, mean = predicted_spread, sd = sigma, lower.tail = FALSE) * 100
  
  return(round(cover_prob, 1))
}

# Get current season and week
current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

# Load current season schedule
cat(paste("Loading", current_season, "season schedule...\n"))
schedule <- load_schedules(seasons = current_season)

# Find upcoming games (games without results)
all_upcoming <- schedule %>%
  filter(is.na(result)) %>%
  filter(gameday >= Sys.Date()) %>%
  arrange(gameday)

if (nrow(all_upcoming) == 0) {
  cat("No upcoming games found. Season may be over.\n")
  quit(save = "no")
}

# Get just the current week (earliest week with unplayed games)
current_week <- min(all_upcoming$week)
upcoming_games <- all_upcoming %>%
  filter(week == current_week)

cat(paste("Current week:", current_week, "\n"))
cat(paste("Found", nrow(upcoming_games), "games this week\n"))

# Load historical data to calculate current team stats
all_games <- readRDS("data/raw_game_data.rds")
features_data <- readRDS("data/features_data.rds")

# Load current season play-by-play for season-average EPA
cat("  Loading current season play-by-play for EPA averages...\n")
current_pbp <- load_pbp(seasons = current_season)

# Calculate season-average EPA for each team (not per-game)
season_epa <- current_pbp %>%
  filter(!is.na(posteam), !is.na(epa)) %>%
  group_by(posteam) %>%
  summarise(
    off_epa_season = mean(epa, na.rm = TRUE),
    success_rate_season = mean(success, na.rm = TRUE),
    plays = n(),
    .groups = "drop"
  )

# Get the most recent stats for each team from features_data
get_team_latest_stats <- function(team, features_data, season_epa) {
  
  home_stats <- features_data %>%
    filter(home_team == team) %>%
    arrange(desc(gameday)) %>%
    slice(1) %>%
    select(
      avg_pts = home_avg_pts,
      avg_pts_allowed = home_avg_pts_allowed,
      win_pct = home_win_pct,
      elo = home_elo_pre,
      recent_form = home_recent_form,
      gameday
    )
  
  away_stats <- features_data %>%
    filter(away_team == team) %>%
    arrange(desc(gameday)) %>%
    slice(1) %>%
    select(
      avg_pts = away_avg_pts,
      avg_pts_allowed = away_avg_pts_allowed,
      win_pct = away_win_pct,
      elo = away_elo_pre,
      recent_form = away_recent_form,
      gameday
    )
  
  # Use whichever is more recent
  if (nrow(home_stats) == 0 && nrow(away_stats) == 0) {
    return(NULL)
  } else if (nrow(home_stats) == 0) {
    stats <- away_stats
  } else if (nrow(away_stats) == 0) {
    stats <- home_stats
  } else if (home_stats$gameday >= away_stats$gameday) {
    stats <- home_stats
  } else {
    stats <- away_stats
  }
  
  # Add season EPA from play-by-play
  team_epa <- season_epa %>% filter(posteam == team)
  if (nrow(team_epa) > 0) {
    stats$off_epa <- team_epa$off_epa_season
    stats$success_rate <- team_epa$success_rate_season
  } else {
    # Fallback to league average if no data
    stats$off_epa <- 0
    stats$success_rate <- 0.5
  }
  
  return(stats)
}

# Calculate rest days for upcoming games
calculate_rest <- function(team, game_date, all_games) {
  # Find team's most recent game
  team_games <- all_games %>%
    filter((home_team == team | away_team == team) & gameday < game_date) %>%
    arrange(desc(gameday)) %>%
    slice(1)
  
  if (nrow(team_games) == 0) {
    return(7)  # Default to 7 days if no previous game found
  }
  
  return(as.numeric(difftime(game_date, team_games$gameday, units = "days")))
}

# Check if teams are in same division
divisions <- data.frame(
  team = c("BUF", "MIA", "NE", "NYJ", "BAL", "CIN", "CLE", "PIT", 
           "HOU", "IND", "JAX", "TEN", "DEN", "KC", "LV", "LAC",
           "DAL", "NYG", "PHI", "WAS", "CHI", "DET", "GB", "MIN",
           "ATL", "CAR", "NO", "TB", "ARI", "LA", "SF", "SEA"),
  division = c(rep("AFC East", 4), rep("AFC North", 4), rep("AFC South", 4), rep("AFC West", 4),
               rep("NFC East", 4), rep("NFC North", 4), rep("NFC South", 4), rep("NFC West", 4)),
  stringsAsFactors = FALSE
)

# Build prediction dataset
predictions_list <- list()

for (i in 1:nrow(upcoming_games)) {
  game <- upcoming_games[i, ]
  
  home_stats <- get_team_latest_stats(game$home_team, features_data, season_epa)
  away_stats <- get_team_latest_stats(game$away_team, features_data, season_epa)
  
  if (is.null(home_stats) || is.null(away_stats)) {
    cat(paste("  Skipping", game$away_team, "@", game$home_team, "- insufficient data\n"))
    next
  }
  
  # Calculate rest days
  home_rest <- calculate_rest(game$home_team, game$gameday, all_games)
  away_rest <- calculate_rest(game$away_team, game$gameday, all_games)
  
  # Check if divisional game
  home_div <- divisions$division[divisions$team == game$home_team]
  away_div <- divisions$division[divisions$team == game$away_team]
  is_divisional <- as.numeric(home_div == away_div)
  
  # Build feature vector with all required predictors
  pred_features <- tibble(
    game_id = game$game_id,
    gameday = game$gameday,
    home_team = game$home_team,
    away_team = game$away_team,
    elo_diff = home_stats$elo - away_stats$elo,
    home_avg_pts = home_stats$avg_pts,
    away_avg_pts = away_stats$avg_pts,
    home_avg_pts_allowed = home_stats$avg_pts_allowed,
    away_avg_pts_allowed = away_stats$avg_pts_allowed,
    home_win_pct = home_stats$win_pct,
    away_win_pct = away_stats$win_pct,
    home_rest = home_rest,
    away_rest = away_rest,
    rest_diff = home_rest - away_rest,
    home_recent_form = home_stats$recent_form,
    away_recent_form = away_stats$recent_form,
    home_off_epa = home_stats$off_epa,
    away_off_epa = away_stats$off_epa,
    home_success_rate = home_stats$success_rate,
    away_success_rate = away_stats$success_rate,
    is_divisional = is_divisional
  )
  
  # Make predictions
  
  # 1. Spread prediction (primary)
  predicted_spread <- predict(models$spread, newdata = pred_features)
  
  # 2. Calculate cover probability for base spread
  cover_prob <- calculate_cover_probability(predicted_spread)
  
  # 3. Calculate win probability from spread (more accurate than overfit GLM)
  # Using normal distribution with sigma ~13.5 points
  sigma <- 13.5
  win_prob_raw <- pnorm(predicted_spread / sigma)
  
  # Cap probabilities to account for NFL uncertainty (no game is truly 100%)
  # Max 95% to acknowledge upsets, min 5% to acknowledge anything can happen
  win_prob <- pmax(0.05, pmin(0.95, win_prob_raw))
  
  predicted_winner <- ifelse(predicted_spread > 0, game$home_team, game$away_team)
  
  # 4. Total points prediction
  predicted_total <- predict(models$total, newdata = pred_features)
  
  # Compile prediction
  prediction <- tibble(
    game_date = game$gameday,
    away_team = game$away_team,
    home_team = game$home_team,
    predicted_winner = predicted_winner,
    home_win_probability = round(win_prob * 100, 1),
    home_win_probability_injury_adjusted = round(win_prob * 100, 1),  # Will be updated by injury script
    predicted_spread = round(predicted_spread, 1),
    cover_probability = cover_prob,  # Paired with predicted_spread
    predicted_spread_injury_adjusted = round(predicted_spread, 1),  # Will be updated by injury script
    cover_probability_injury_adjusted = cover_prob,  # Will be updated by injury script
    injury_impact = 0,  # Will be updated by injury script
    predicted_spread_weather_adjusted = round(predicted_spread, 1),  # Will be updated by weather script
    cover_probability_weather_adjusted = cover_prob,  # Will be updated by weather script
    adjusted_spread = round(predicted_spread, 1),  # Final cumulative value
    adjusted_cover_probability = cover_prob,  # Final cumulative value
    predicted_total = round(predicted_total, 1),
    prediction_date = Sys.Date(),
    temp = NA_real_,  # Will be updated by weather script
    wind_speed = NA_real_,  # Will be updated by weather script
    precipitation = NA_real_,  # Will be updated by weather script
    weather_impact = 0  # Will be updated by weather script
  )
  
  predictions_list[[i]] <- prediction
}

# Combine all predictions
all_predictions <- bind_rows(predictions_list)

if (nrow(all_predictions) == 0) {
  cat("No predictions could be generated.\n")
  quit(save = "no")
}

cat(paste("\n✓ Generated predictions for", nrow(all_predictions), "games\n"))

# Save as latest predictions only (dated copy will be created at end of pipeline)
write.csv(all_predictions, "data/predictions/latest_predictions.csv", row.names = FALSE)
cat("✓ Saved as data/predictions/latest_predictions.csv\n")

# Display predictions
cat("\n=== PREDICTIONS ===\n")
print(all_predictions %>% select(away_team, home_team, predicted_spread, cover_probability, predicted_total), n = Inf)

cat("\n=== Model Performance (from training) ===\n")
cat(paste("Winner Accuracy:", round(models$accuracy * 100, 1), "%\n"))
cat(paste("Spread MAE:", round(models$spread_mae, 2), "points\n"))
cat(paste("Total MAE:", round(models$total_mae, 2), "points\n"))