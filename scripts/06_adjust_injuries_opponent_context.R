# NFL Predictions Model - Injury Adjustment with Opponent Context
# This script adjusts predictions based on injuries with opponent-specific weights
# v3 FIXES:
# - QB recency check now requires 50+ attempts in last 3 weeks (starter-level playing time)
# - Prevents penalties for backup QBs with garbage time attempts
# v4 FIXES:
# - Added retry logic with exponential backoff for ESPN API
# - Cached injury data to avoid duplicate API calls

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
})

# Load error handling utilities
source("scripts/00_error_handling.R")

cat("Adjusting predictions for injuries...\n")

# Load base predictions from appropriate file (configured in run_weekly_predictions.R)
latest_file <- Sys.getenv("LATEST_FILE", "data/predictions/latest_predictions.csv")
base_predictions <- read.csv(latest_file, stringsAsFactors = FALSE)

# Team name to abbreviation mapping
team_map <- c(
  "Arizona Cardinals" = "ARI", "Atlanta Falcons" = "ATL", "Baltimore Ravens" = "BAL",
  "Buffalo Bills" = "BUF", "Carolina Panthers" = "CAR", "Chicago Bears" = "CHI",
  "Cincinnati Bengals" = "CIN", "Cleveland Browns" = "CLE", "Dallas Cowboys" = "DAL",
  "Denver Broncos" = "DEN", "Detroit Lions" = "DET", "Green Bay Packers" = "GB",
  "Houston Texans" = "HOU", "Indianapolis Colts" = "IND", "Jacksonville Jaguars" = "JAX",
  "Kansas City Chiefs" = "KC", "Las Vegas Raiders" = "LV", "Los Angeles Chargers" = "LAC",
  "Los Angeles Rams" = "LA", "Miami Dolphins" = "MIA", "Minnesota Vikings" = "MIN",
  "New England Patriots" = "NE", "New Orleans Saints" = "NO", "New York Giants" = "NYG",
  "New York Jets" = "NYJ", "Philadelphia Eagles" = "PHI", "Pittsburgh Steelers" = "PIT",
  "San Francisco 49ers" = "SF", "Seattle Seahawks" = "SEA", "Tampa Bay Buccaneers" = "TB",
  "Tennessee Titans" = "TEN", "Washington Commanders" = "WAS"
)

# Function to get injury data from ESPN
get_injury_data <- function() {
  url <- "https://site.web.api.espn.com/apis/site/v2/sports/football/nfl/injuries"
  
  tryCatch({
    response <- GET(url, add_headers(`User-Agent` = "Mozilla/5.0"))
    if (status_code(response) != 200) return(NULL)
    
    data <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)
    all_injuries <- list()
    
    if (!is.null(data$injuries)) {
      for (team_entry in data$injuries) {
        team_name <- team_entry$displayName
        team_abbr <- team_map[team_name]
        if (is.null(team_abbr) || is.na(team_abbr) || team_abbr == "") next
        
        if (!is.null(team_entry$injuries) && length(team_entry$injuries) > 0) {
          for (injury in team_entry$injuries) {
            if (is.null(injury$athlete) || is.null(injury$status)) next
            
            player_name <- if (!is.null(injury$athlete$displayName)) injury$athlete$displayName else "Unknown"
            position <- "UNK"
            if (!is.null(injury$athlete$position)) {
              if (!is.null(injury$athlete$position$abbreviation)) {
                position <- injury$athlete$position$abbreviation
              }
            }
            status <- if (!is.null(injury$status)) injury$status else "Unknown"
            injury_detail <- ""
            if (!is.null(injury$details)) {
              if (!is.null(injury$details$fantasyStatus)) {
                injury_detail <- injury$details$fantasyStatus
              }
            }
            
            if (player_name != "Unknown" && status != "Unknown") {
              all_injuries[[length(all_injuries) + 1]] <- data.frame(
                team = as.character(team_abbr),
                player = as.character(player_name),
                position = as.character(position),
                status = as.character(status),
                details = as.character(injury_detail),
                stringsAsFactors = FALSE
              )
            }
          }
        }
      }
    }
    
    if (length(all_injuries) > 0) {
      return(do.call(rbind, all_injuries))
    } else {
      return(NULL)
    }
  }, error = function(e) {
    cat(paste("Error fetching injury data:", e$message, "\n"))
    return(NULL)
  })
}

# Load additional data with retry logic
cat("  Fetching injury reports from ESPN...\n")
injuries <- safe_network_call(
  func = get_injury_data,
  max_retries = 3,
  initial_delay = 2,
  script_name = "06_adjust_injuries_opponent_context.R",
  operation = "ESPN injury data fetch"
)

# Supplement ESPN with nflreadr roster data for IR QBs (ESPN often omits long-term IR)
# Use explicit season for 2025 NFL season
rosters <- load_rosters(seasons = 2025)

ir_qbs_nflreadr <- rosters %>%
  filter(position == "QB", status %in% c("RES", "IR", "PUP")) %>%
  select(team, full_name, status)

if (nrow(ir_qbs_nflreadr) > 0) {
  ir_qbs_to_add <- data.frame(
    team = ir_qbs_nflreadr$team,
    player = ir_qbs_nflreadr$full_name,
    position = "QB",
    status = "Injured Reserve",
    details = "IR",
    stringsAsFactors = FALSE
  )
  
  if (!is.null(injuries)) {
    injuries <- rbind(injuries, ir_qbs_to_add)
  } else {
    injuries <- ir_qbs_to_add
  }
  
  cat(paste("  Added", nrow(ir_qbs_to_add), "IR QBs from nflreadr rosters\n"))
}

# Remove duplicates but preserve IR QBs for detection
if (!is.null(injuries)) {
  injuries <- injuries %>%
    distinct(team, player, position, .keep_all = TRUE)
  
  # Keep IR QBs for injury penalty calculation
  ir_qbs <- injuries %>%
    filter(position == "QB", grepl("INJURED RESERVE|IR", toupper(status)))
  
  # Remove non-QB IR players (already baked into stats)
  injuries_for_calc <- injuries %>%
    filter(!grepl("INJURED RESERVE|NFI-R|PUP-R", toupper(status)) | 
             (position == "QB" & grepl("INJURED RESERVE|IR", toupper(status))))
  
  cat(paste("  Removed duplicates and non-QB IR players, processing", nrow(injuries_for_calc), "unique injuries\n"))
  cat(paste("  Tracking", nrow(ir_qbs), "IR QBs for penalty calculation\n"))
  
  injuries <- injuries_for_calc
}

if (is.null(injuries)) {
  cat("⚠️  WARNING: Could not fetch injury data - predictions will use base model only\n")
  cat("    Check ESPN API or review injury status manually before betting\n")
}

defense_ratings <- NULL
if (file.exists("data/defense_ratings.rds")) {
  defense_ratings <- readRDS("data/defense_ratings.rds")
  cat("  Loaded defensive quality ratings\n")
}

qb_performance_data <- NULL
if (file.exists("data/qb_performance.rds")) {
  qb_performance_data <- readRDS("data/qb_performance.rds")
  cat("  Loaded backup QB performance database\n")
}

# Position impact weights
position_weights <- data.frame(
  position = c("QB", "RB", "WR", "TE", "T", "G", "C", "DE", "DT", "LB", "CB", "S", "K", "P"),
  out_impact = c(6.5, 1.5, 1.2, 1.0, 2.0, 1.5, 1.8, 2.0, 1.5, 1.0, 1.2, 0.8, 0.5, 0.3),
  doubtful_impact = c(4.5, 1.0, 0.8, 0.7, 1.4, 1.0, 1.2, 1.4, 1.0, 0.7, 0.8, 0.5, 0.3, 0.2),
  questionable_impact = c(2.0, 0.5, 0.3, 0.3, 0.7, 0.5, 0.6, 0.7, 0.5, 0.3, 0.4, 0.2, 0.1, 0.1),
  stringsAsFactors = FALSE
)

# Calculate injury impact for a team with QB-specific handling
calculate_team_injury_impact <- function(team_abbr, opponent_abbr, injuries_df, position_weights, defense_ratings = NULL, qb_performance_data = NULL, current_season_pbp = NULL) {
  
  if (is.null(injuries_df)) {
    return(list(impact = 0, details = ""))
  }
  
  team_injuries <- injuries_df[injuries_df$team == team_abbr, ]
  if (nrow(team_injuries) == 0) {
    return(list(impact = 0, details = ""))
  }
  
  total_impact <- 0
  injury_details <- c()
  
  # Handle QB injuries separately - includes IR QBs
  qb_injuries <- team_injuries[team_injuries$position == "QB" & 
                                 grepl("OUT|DOUBTFUL|INJURED RESERVE|IR", toupper(team_injuries$status)), ]
  
  if (nrow(qb_injuries) > 0 && !is.null(qb_performance_data) && !is.null(current_season_pbp)) {
    team_qbs <- qb_performance_data[qb_performance_data$team == team_abbr, ]
    
    # Find the INJURED QB in roster data by name matching
    injured_qb_name <- qb_injuries$player[1]
    
    injured_qb <- team_qbs[sapply(team_qbs$full_name, function(name) {
      grepl(injured_qb_name, name, ignore.case = TRUE) | grepl(name, injured_qb_name, ignore.case = TRUE)
    }), ]
    
    if (nrow(injured_qb) > 0) {
      injured_qb <- injured_qb[1, ]
      
      # v3 FIX: Check if injured QB has STARTER-LEVEL playing time in last 3 weeks
      # Require 50+ attempts (roughly 1+ full game as starter)
      # This filters out:
      # - Long-term IR QBs (Burrow, Watson, etc.)
      # - Backup QBs with garbage time attempts (Richardson with 5 attempts)
      # - QBs who came in for one drive
      recent_week_threshold <- max(current_season_pbp$week, na.rm = TRUE) - 3
      
      injured_qb_recent_attempts <- current_season_pbp %>%
        filter(passer_player_id == injured_qb$gsis_id,
               week >= recent_week_threshold) %>%
        nrow()
      
      if (injured_qb_recent_attempts < 50) {
        # QB doesn't have starter-level playing time - skip penalty
        cat(paste("  ✓ Skipping", injured_qb$full_name, "for", team_abbr, "- only", injured_qb_recent_attempts, "attempts in last 3 weeks (not active starter)\n"))
        # Don't apply penalty, but still note it in the report for transparency
        injury_details <- c(injury_details, paste0(injured_qb$full_name, " (QB - LONG-TERM IR, no penalty)"))
      } else {
        # QB has starter-level playing time - this is a REAL injury that affects this week
        cat(paste("  → Processing active QB injury:", injured_qb$full_name, "for", team_abbr, "(", injured_qb_recent_attempts, "attempts in last 3 weeks)\n"))
        
        # Find REPLACEMENT - next available QB not injured
        remaining_qbs <- team_qbs[team_qbs$gsis_id != injured_qb$gsis_id, ]
        
        # Sort by depth chart position (from nflreadr), then by pass attempts as tiebreaker
        remaining_qbs <- remaining_qbs[order(remaining_qbs$depth_chart_position, -remaining_qbs$pass_attempts, na.last = TRUE), ]
        
        if (nrow(remaining_qbs) > 0) {
          replacement_qb <- remaining_qbs[1, ]
          
          # Compare INJURED vs REPLACEMENT
          league_avg <- 0.05
          injured_epa <- ifelse(injured_qb$has_history, injured_qb$epa_per_play, league_avg)
          replacement_epa <- ifelse(replacement_qb$has_history, replacement_qb$epa_per_play, league_avg - 0.05)
          
          epa_diff <- injured_qb$epa_per_play - replacement_qb$epa_per_play
          qb_impact <- epa_diff * 65
          
          # Cap based on backup quality
          if (!is.na(replacement_epa) && replacement_epa > 0.0) {
            # Competent backup (positive EPA) - cap at 5 points
            qb_impact <- min(max(qb_impact, 1), 5)
            cat(paste("    Competent backup detected, capped at 5 points\n"))
          } else {
            # Poor backup - cap at 7 points (reduced from 10)
            qb_impact <- min(max(qb_impact, 2), 7)
            cat(paste("    Poor backup detected, capped at 7 points\n"))
          }
          
          # QB injuries are critical regardless of opponent defense - no multiplier
          
          total_impact <- total_impact + qb_impact
          
          # Indicate if this is an IR situation
          ir_status <- ifelse(grepl("INJURED RESERVE|IR", toupper(qb_injuries$status[1])), "IR", "OUT")
          injury_details <- c(injury_details, paste0(injured_qb$full_name, " (QB - ", ir_status, ", ", 
                                                     replacement_qb$full_name, " starting)"))
          
          cat(paste("    Applied", round(qb_impact, 2), "point penalty\n"))
        } else {
          # Fallback if no replacement found (shouldn't happen)
          qb_impact <- 5.0  # Conservative penalty
          total_impact <- total_impact + qb_impact
          injury_details <- c(injury_details, paste0(injured_qb_name, " (QB - OUT)"))
          cat(paste("    No replacement found, applied default 5 point penalty\n"))
        }
      }
    } else {
      # Fallback if name matching fails
      cat(paste("  ⚠️  Could not match QB name:", injured_qb_name, "for", team_abbr, "\n"))
      qb_impact <- 4.0  # Conservative penalty
      total_impact <- total_impact + qb_impact
      injury_details <- c(injury_details, paste0(injured_qb_name, " (QB - OUT)"))
    }
  }
  
  # Handle non-QB injuries (excludes ALL QBs and IR players)
  non_qb_injuries <- team_injuries[team_injuries$position != "QB" & 
                                     !grepl("INJURED RESERVE|IR", toupper(team_injuries$status)), ]
  
  for (i in 1:nrow(non_qb_injuries)) {
    injury <- non_qb_injuries[i, ]
    status <- toupper(injury$status)
    position <- injury$position
    player <- injury$player
    
    weight_row <- position_weights[position_weights$position == position, ]
    
    if (nrow(weight_row) == 0) {
      impact <- 0
    } else {
      if (grepl("OUT", status)) {
        impact <- weight_row$out_impact
        injury_details <- c(injury_details, paste0(player, " (", position, " - OUT)"))
      } else if (grepl("DOUBTFUL", status)) {
        impact <- weight_row$doubtful_impact
        injury_details <- c(injury_details, paste0(player, " (", position, " - DOUBTFUL)"))
      } else if (grepl("QUESTIONABLE", status)) {
        impact <- weight_row$questionable_impact
        injury_details <- c(injury_details, paste0(player, " (", position, " - QUESTIONABLE)"))
      } else {
        impact <- 0
      }
    }
    
    if (!is.null(defense_ratings) && impact > 0) {
      opp_defense <- defense_ratings[defense_ratings$defteam == opponent_abbr, ]
      if (nrow(opp_defense) > 0) {
        if (position %in% c("WR", "TE")) {
          multiplier <- opp_defense$pass_defense_multiplier
        } else if (position == "RB") {
          multiplier <- opp_defense$rush_defense_multiplier
        } else if (position %in% c("T", "G", "C")) {
          multiplier <- 0.6 * opp_defense$pass_defense_multiplier + 
            0.4 * opp_defense$rush_defense_multiplier
        } else {
          multiplier <- 1.0
        }
        impact <- impact * multiplier
      }
    }
    
    total_impact <- total_impact + impact
  }
  
  return(list(
    impact = total_impact,
    details = if(length(injury_details) > 0) paste(injury_details, collapse = "; ") else ""
  ))
}

# Load current season play-by-play for QB recency check
cat("  Loading current season play-by-play for QB recency check...\n")
current_season <- year(Sys.Date())
if (month(Sys.Date()) < 3) {
  current_season <- current_season - 1
}

current_season_pbp <- NULL
tryCatch({
  current_season_pbp <- load_pbp(seasons = current_season)
  cat(paste("  ✓ Loaded", current_season, "play-by-play data\n"))
}, error = function(e) {
  cat(paste("  ⚠️  Could not load current season PBP:", e$message, "\n"))
  cat("  QB recency check will be skipped\n")
})

# Apply injury adjustments
if (is.null(injuries)) {
  cat("  No injury data available - using base predictions only\n")
  
  base_predictions$spread_after_injuries <- base_predictions$predicted_spread
  base_predictions$home_win_probability_after_injuries <- base_predictions$home_win_probability
  base_predictions$injury_impact <- 0
  base_predictions$home_injury_impact <- 0
  base_predictions$away_injury_impact <- 0
  base_predictions$home_injuries <- ""
  base_predictions$away_injuries <- ""
  
} else {
  cat(paste("  Found injury data for", length(unique(injuries$team)), "teams\n"))
  
  adjusted_predictions <- base_predictions
  adjusted_predictions$home_injury_impact <- 0
  adjusted_predictions$away_injury_impact <- 0
  adjusted_predictions$home_injuries <- ""
  adjusted_predictions$away_injuries <- ""
  
  for (i in 1:nrow(adjusted_predictions)) {
    home_team <- adjusted_predictions$home_team[i]
    away_team <- adjusted_predictions$away_team[i]
    
    cat(paste("\n  Analyzing injuries for", away_team, "@", home_team, "\n"))
    
    home_impact_data <- calculate_team_injury_impact(home_team, away_team, injuries, position_weights, defense_ratings, qb_performance_data, current_season_pbp)
    away_impact_data <- calculate_team_injury_impact(away_team, home_team, injuries, position_weights, defense_ratings, qb_performance_data, current_season_pbp)
    
    adjusted_predictions$home_injury_impact[i] <- home_impact_data$impact
    adjusted_predictions$away_injury_impact[i] <- away_impact_data$impact
    adjusted_predictions$home_injuries[i] <- home_impact_data$details
    adjusted_predictions$away_injuries[i] <- away_impact_data$details
  }
  
  adjusted_predictions$injury_impact <- adjusted_predictions$away_injury_impact - adjusted_predictions$home_injury_impact
  adjusted_predictions$spread_after_injuries <- 
    adjusted_predictions$predicted_spread + adjusted_predictions$injury_impact
  
  # Update predicted winner based on injury-adjusted spread
  adjusted_predictions$predicted_winner <- ifelse(
    adjusted_predictions$spread_after_injuries > 0,
    adjusted_predictions$home_team,
    adjusted_predictions$away_team
  )
  
  # Calculate win probability after injuries (will be updated again after weather)
  sigma <- 13.5
  adjusted_predictions$home_win_probability_after_injuries <- 
    pnorm(adjusted_predictions$spread_after_injuries / sigma) * 100
  
  # Remove duplicate injuries in text descriptions
  for (i in 1:nrow(adjusted_predictions)) {
    if (adjusted_predictions$home_injuries[i] != "") {
      injuries_list <- strsplit(adjusted_predictions$home_injuries[i], "; ")[[1]]
      unique_injuries <- unique(injuries_list)
      adjusted_predictions$home_injuries[i] <- paste(unique_injuries, collapse = "; ")
    }
    if (adjusted_predictions$away_injuries[i] != "") {
      injuries_list <- strsplit(adjusted_predictions$away_injuries[i], "; ")[[1]]
      unique_injuries <- unique(injuries_list)
      adjusted_predictions$away_injuries[i] <- paste(unique_injuries, collapse = "; ")
    }
  }
  
  base_predictions <- adjusted_predictions
  
  cat(paste("\n✓ Applied injury adjustments to", nrow(base_predictions), "games\n"))
}

# Export detailed injury report for manual verification (includes ALL injuries including IR)
# Re-use cached injury data instead of calling API again
if (!is.null(injuries)) {
  all_injuries_for_export <- injuries

  # Add IR QBs from nflreadr to the export
  rosters_for_export <- load_rosters(seasons = 2025)
  ir_qbs_for_export <- rosters_for_export %>%
    filter(position == "QB", status %in% c("RES", "IR", "PUP")) %>%
    select(team, full_name, status)
  
  if (nrow(ir_qbs_for_export) > 0) {
    ir_qbs_export_df <- data.frame(
      team = ir_qbs_for_export$team,
      player = ir_qbs_for_export$full_name,
      position = "QB",
      status = paste("Injured Reserve -", ir_qbs_for_export$status),
      details = "IR",
      stringsAsFactors = FALSE
    )
    
    if (!is.null(all_injuries_for_export)) {
      all_injuries_for_export <- rbind(all_injuries_for_export, ir_qbs_export_df)
    } else {
      all_injuries_for_export <- ir_qbs_export_df
    }
  }
  
  if (!is.null(all_injuries_for_export)) {
    all_injuries_for_export <- all_injuries_for_export %>%
      distinct(team, player, position, .keep_all = TRUE)
    
    injury_report <- all_injuries_for_export %>%
      filter(grepl("OUT|DOUBTFUL|QUESTIONABLE|INJURED RESERVE|IR|PUP|NFI|RES", toupper(status))) %>%
      arrange(team, 
              factor(position, levels = c("QB", "RB", "WR", "TE", "T", "G", "C", "DE", "DT", "LB", "CB", "S")),
              status)
    
    write.csv(injury_report, "data/injury_report.csv", row.names = FALSE)
    cat("✓ Injury report saved (includes IR QBs from nflreadr)\n")
  }
}

# Select and order columns for better readability
# Note: We keep intermediate columns here; weather script will do final selection
final_predictions <- base_predictions %>%
  select(
    # Keep everything for now - weather script will finalize
    game_date, away_team, home_team, predicted_winner,
    home_win_probability, 
    home_win_probability_after_injuries,
    predicted_spread,
    spread_after_injuries,
    injury_impact,
    home_injury_impact,
    away_injury_impact,
    predicted_total,
    prediction_date,
    home_injuries,
    away_injuries
  )

# Save to appropriate file based on run type (configured in run_weekly_predictions.R)
latest_file <- Sys.getenv("LATEST_FILE", "data/predictions/latest_predictions.csv")

# Use safe write with backup
safe_write_csv(
  data = final_predictions,
  file_path = latest_file,
  script_name = "06_adjust_injuries_opponent_context.R",
  backup = TRUE
)
cat(paste("✓ Updated", latest_file, "with injury adjustments\n"))

significant_injuries <- final_predictions[abs(final_predictions$injury_impact) >= 3, ]
if (nrow(significant_injuries) > 0) {
  cat("\n=== Games with Significant Injury Impact (3+ points) ===\n")
  for (i in 1:nrow(significant_injuries)) {
    game <- significant_injuries[i, ]
    cat(paste0(
      game$away_team, " @ ", game$home_team, 
      " | Base spread: ", round(game$predicted_spread, 1),
      " → After injuries: ", round(game$spread_after_injuries, 1),
      " (", ifelse(game$injury_impact > 0, "+", ""), round(game$injury_impact, 1), ")\n"
    ))
  }
}

cat("\n=== v3 KEY FEATURES ===\n")
cat("✓ QB recency check: Requires 50+ attempts in last 3 weeks (starter-level playing time)\n")
cat("✓ Filters out: Long-term IR QBs, backup QBs with garbage time attempts\n")
cat("✓ QB penalty caps: 5 points (good backup) / 7 points (poor backup)\n")
cat("✓ Detailed logging shows attempt counts for transparency\n")
cat("✓ All injury detail columns preserved\n")
cat("\n✓ Injury adjustment complete\n")
