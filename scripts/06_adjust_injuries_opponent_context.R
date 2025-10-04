# NFL Predictions Model - Injury Adjustment with Opponent Context
# This script adjusts predictions based on injuries with opponent-specific weights

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
})

cat("Adjusting predictions for injuries...\n")

# Load base predictions
base_predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

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

# Load additional data
cat("  Fetching injury reports from ESPN...\n")
injuries <- get_injury_data()

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
calculate_team_injury_impact <- function(team_abbr, opponent_abbr, injuries_df, position_weights, defense_ratings = NULL, qb_performance_data = NULL) {
  
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
  
  if (nrow(qb_injuries) > 0 && !is.null(qb_performance_data)) {
    team_qbs <- qb_performance_data[qb_performance_data$team == team_abbr, ]
    
    # Find the INJURED QB in roster data by name matching
    injured_qb_name <- qb_injuries$player[1]
    
    injured_qb <- team_qbs[sapply(team_qbs$full_name, function(name) {
      grepl(injured_qb_name, name, ignore.case = TRUE) | grepl(name, injured_qb_name, ignore.case = TRUE)
    }), ]
    
    if (nrow(injured_qb) > 0) {
      injured_qb <- injured_qb[1, ]
      
      # Check if injured QB has actually played this season
      # If they have 0 current season attempts, they were already replaced/out
      if (!is.null(injured_qb$current_season_attempts) && injured_qb$current_season_attempts > 0) {
        # QB was actually playing - calculate penalty for losing them
        
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
          qb_impact <- min(max(qb_impact, 2), 10)
          
          # QB injuries are critical regardless of opponent defense - no multiplier
          
          total_impact <- total_impact + qb_impact
          
          # Indicate if this is an IR situation
          ir_status <- ifelse(grepl("INJURED RESERVE|IR", toupper(qb_injuries$status[1])), "IR", "OUT")
          injury_details <- c(injury_details, paste0(injured_qb$full_name, " (QB - ", ir_status, ", ", 
                                                     replacement_qb$full_name, " starting)"))
        }
      } else {
        # QB has 0 current season attempts - was already replaced before this week
        # No penalty because team has already been playing without them
        cat(paste("  Note:", injured_qb$full_name, "on IR for", team_abbr, "but has not played this season - no penalty applied\n"))
      }
    } else {
      # Fallback if name matching fails
      qb_impact <- 6.5
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

# Apply injury adjustments
if (is.null(injuries)) {
  cat("  No injury data available - using base predictions only\n")
  
  base_predictions$predicted_spread_injury_adjusted <- base_predictions$predicted_spread
  base_predictions$home_win_probability_injury_adjusted <- base_predictions$home_win_probability
  base_predictions$injury_impact <- 0
  base_predictions$key_injuries <- ""
  
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
    
    home_impact_data <- calculate_team_injury_impact(home_team, away_team, injuries, position_weights, defense_ratings, qb_performance_data)
    away_impact_data <- calculate_team_injury_impact(away_team, home_team, injuries, position_weights, defense_ratings, qb_performance_data)
    
    adjusted_predictions$home_injury_impact[i] <- home_impact_data$impact
    adjusted_predictions$away_injury_impact[i] <- away_impact_data$impact
    adjusted_predictions$home_injuries[i] <- home_impact_data$details
    adjusted_predictions$away_injuries[i] <- away_impact_data$details
  }
  
  adjusted_predictions$injury_impact <- adjusted_predictions$away_injury_impact - adjusted_predictions$home_injury_impact
  adjusted_predictions$predicted_spread_injury_adjusted <- 
    adjusted_predictions$predicted_spread + adjusted_predictions$injury_impact
  
  # Update predicted winner based on injury-adjusted spread
  adjusted_predictions$predicted_winner <- ifelse(
    adjusted_predictions$predicted_spread_injury_adjusted > 0,
    adjusted_predictions$home_team,
    adjusted_predictions$away_team
  )
  
  sigma <- 13.5
  adjusted_predictions$home_win_probability_injury_adjusted <- 
    pnorm(adjusted_predictions$predicted_spread_injury_adjusted / sigma) * 100
  
  adjusted_predictions$key_injuries <- ifelse(
    adjusted_predictions$home_injuries != "" | adjusted_predictions$away_injuries != "",
    paste0(
      ifelse(adjusted_predictions$home_injuries != "", 
             paste0(adjusted_predictions$home_team, ": ", adjusted_predictions$home_injuries), ""),
      ifelse(adjusted_predictions$home_injuries != "" & adjusted_predictions$away_injuries != "", " | ", ""),
      ifelse(adjusted_predictions$away_injuries != "", 
             paste0(adjusted_predictions$away_team, ": ", adjusted_predictions$away_injuries), "")
    ),
    ""
  )
  
  # Remove duplicate injuries
  for (i in 1:nrow(adjusted_predictions)) {
    if (adjusted_predictions$key_injuries[i] != "") {
      injuries_list <- strsplit(adjusted_predictions$key_injuries[i], "; ")[[1]]
      unique_injuries <- unique(injuries_list)
      adjusted_predictions$key_injuries[i] <- paste(unique_injuries, collapse = "; ")
    }
  }
  
  base_predictions <- adjusted_predictions %>%
    select(game_date, away_team, home_team, predicted_winner, 
           home_win_probability, home_win_probability_injury_adjusted,
           predicted_spread, predicted_spread_injury_adjusted, injury_impact,
           predicted_total, prediction_date)
  
  cat(paste("  Applied injury adjustments to", nrow(base_predictions), "games\n"))
}

# Export detailed injury report for manual verification (includes ALL injuries including IR)
if (!is.null(injuries)) {
  # Use the injuries dataframe that already has IR QBs added from nflreadr
  # Note: 'injuries' at this point has been filtered to remove non-QB IR players
  # So we need to get the original injuries before filtering, then add IR QBs
  
  all_injuries_for_export <- get_injury_data()
  
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

write.csv(base_predictions, "data/predictions/latest_predictions.csv", row.names = FALSE)
cat("✓ Updated predictions with injury adjustments\n")

significant_injuries <- base_predictions[abs(base_predictions$injury_impact) >= 3, ]
if (nrow(significant_injuries) > 0) {
  cat("\n=== Games with Significant Injury Impact (3+ points) ===\n")
  for (i in 1:nrow(significant_injuries)) {
    game <- significant_injuries[i, ]
    cat(paste0(
      game$away_team, " @ ", game$home_team, 
      " | Base spread: ", round(game$predicted_spread, 1),
      " → Adjusted: ", round(game$predicted_spread_injury_adjusted, 1),
      " (", ifelse(game$injury_impact > 0, "+", ""), round(game$injury_impact, 1), ")\n"
    ))
  }
}