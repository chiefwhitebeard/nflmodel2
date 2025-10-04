# NFL Predictions Model - Data Loading Script
# This script loads and prepares historical NFL data using nflreadr

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(lubridate)
})

cat("Loading NFL data...\n")

# Get current season
current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

# Load team statistics from multiple seasons
# We'll use 3+ seasons of data for training
seasons_to_load <- (current_season - 3):current_season

cat(paste("Loading seasons:", paste(seasons_to_load, collapse = ", "), "\n"))

# Load schedule data which includes game results
team_stats_list <- list()

for (season in seasons_to_load) {
  cat(paste("  Loading", season, "season...\n"))
  
  tryCatch({
    # Load team schedule to get game results
    schedule <- load_schedules(seasons = season)
    
    # Filter to games with results only
    schedule <- schedule[!is.na(schedule$result), ]
    
    # Select relevant columns
    schedule <- schedule[, c("season", "week", "game_id", "gameday",
                             "home_team", "away_team", 
                             "home_score", "away_score",
                             "result", "total",
                             "home_rest", "away_rest",
                             "roof", "surface")]
    
    team_stats_list[[as.character(season)]] <- schedule
    cat(paste("    Loaded", nrow(schedule), "games\n"))
    
  }, error = function(e) {
    cat(paste("  Warning: Could not load data for", season, "-", e$message, "\n"))
  })
}

# Combine all seasons
all_games <- do.call(rbind, team_stats_list)

if (is.null(all_games) || nrow(all_games) == 0) {
  stop("ERROR: No game data was loaded. Check your internet connection and try again.")
}

cat(paste("\n✓ Loaded", nrow(all_games), "games from", 
          length(unique(all_games$season)), "seasons\n"))

# Save the raw data
saveRDS(all_games, "data/raw_game_data.rds")
cat("✓ Saved raw data to data/raw_game_data.rds\n")

# Quick summary
cat("\nData Summary:\n")
cat(paste("  Seasons:", paste(unique(all_games$season), collapse = ", "), "\n"))
cat(paste("  Total games:", nrow(all_games), "\n"))
cat(paste("  Date range:", min(all_games$gameday), "to", max(all_games$gameday), "\n"))