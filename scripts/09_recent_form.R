# NFL Predictions Model - Recent Form and Momentum
# This script calculates recent performance trends vs season averages

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

cat("Calculating recent form and momentum...\n")

# Load game data
all_games <- readRDS("data/raw_game_data.rds")

# Get current predictions
predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

# Calculate team recent form (last 3-4 games) vs season average
calculate_recent_form <- function(games, team, recent_n = 4) {
  
  team_games <- games[games$home_team == team | games$away_team == team, ]
  team_games <- team_games[order(team_games$gameday), ]
  
  if (nrow(team_games) < recent_n + 5) {
    return(NULL)  # Not enough games
  }
  
  # Separate team stats
  team_games$is_home <- team_games$home_team == team
  team_games$points_for <- ifelse(team_games$is_home, team_games$home_score, team_games$away_score)
  team_games$points_against <- ifelse(team_games$is_home, team_games$away_score, team_games$home_score)
  team_games$point_diff <- team_games$points_for - team_games$points_against
  
  # Season averages (excluding most recent games)
  season_avg_diff <- mean(head(team_games$point_diff, -recent_n), na.rm = TRUE)
  
  # Recent form (last N games)
  recent_games <- tail(team_games, recent_n)
  recent_avg_diff <- mean(recent_games$point_diff, na.rm = TRUE)
  
  # Momentum = recent form - season average
  momentum <- recent_avg_diff - season_avg_diff
  
  return(list(
    season_avg = season_avg_diff,
    recent_avg = recent_avg_diff,
    momentum = momentum
  ))
}

# Calculate momentum for all teams
all_teams <- unique(c(all_games$home_team, all_games$away_team))

team_momentum <- data.frame(
  team = character(),
  season_avg_diff = numeric(),
  recent_avg_diff = numeric(),
  momentum = numeric(),
  stringsAsFactors = FALSE
)

for (team in all_teams) {
  form <- calculate_recent_form(all_games, team, recent_n = 4)
  if (!is.null(form)) {
    team_momentum <- rbind(team_momentum, data.frame(
      team = team,
      season_avg_diff = form$season_avg,
      recent_avg_diff = form$recent_avg,
      momentum = form$momentum,
      stringsAsFactors = FALSE
    ))
  }
}

cat(paste("✓ Calculated momentum for", nrow(team_momentum), "teams\n"))

# Apply momentum adjustment to predictions
predictions$momentum_adjustment <- 0

for (i in 1:nrow(predictions)) {
  home_team <- predictions$home_team[i]
  away_team <- predictions$away_team[i]
  
  home_momentum <- team_momentum$momentum[team_momentum$team == home_team]
  away_momentum <- team_momentum$momentum[team_momentum$team == away_team]
  
  if (length(home_momentum) > 0 && length(away_momentum) > 0) {
    # Net momentum advantage
    momentum_diff <- home_momentum - away_momentum
    
    # Scale momentum (cap at +/- 3 points)
    momentum_adjustment <- max(min(momentum_diff * 0.3, 3), -3)
    
    predictions$momentum_adjustment[i] <- momentum_adjustment
  }
}

# Apply momentum to spread
predictions$predicted_spread_final <- 
  predictions$predicted_spread_weather_adjusted + predictions$momentum_adjustment

# Recalculate win probability with final spread
sigma <- 13.5
predictions$home_win_probability_final <- 
  pnorm(predictions$predicted_spread_final / sigma) * 100

cat(paste("✓ Applied momentum adjustments\n"))

# Save final predictions
write.csv(predictions, "data/predictions/latest_predictions.csv", row.names = FALSE)

# Show teams with significant momentum shifts
hot_teams <- team_momentum[team_momentum$momentum > 5, ]
cold_teams <- team_momentum[team_momentum$momentum < -5, ]

if (nrow(hot_teams) > 0) {
  cat("\n=== Hot Teams (momentum > +5 pts) ===\n")
  hot_teams <- hot_teams[order(-hot_teams$momentum), ]
  for (i in 1:min(5, nrow(hot_teams))) {
    cat(paste0(hot_teams$team[i], ": ", round(hot_teams$momentum[i], 1), " pts\n"))
  }
}

if (nrow(cold_teams) > 0) {
  cat("\n=== Cold Teams (momentum < -5 pts) ===\n")
  cold_teams <- cold_teams[order(cold_teams$momentum), ]
  for (i in 1:min(5, nrow(cold_teams))) {
    cat(paste0(cold_teams$team[i], ": ", round(cold_teams$momentum[i], 1), " pts\n"))
  }
}

cat("\n✓ Recent form adjustments complete\n")