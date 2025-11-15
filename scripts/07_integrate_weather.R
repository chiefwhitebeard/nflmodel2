# NFL Predictions Model - Weather Integration
# This script fetches weather forecasts and adjusts predictions accordingly
# v3 FIXES:
# - Precipitation now correctly converted from mm to inches
# - Win probability calculated from final spread (includes weather)

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(lubridate)
})

cat("Integrating weather data...\n")

# Stadium locations (lat/lon) for weather API calls
stadium_locations <- data.frame(
  team = c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN",
           "DET", "GB", "HOU", "IND", "JAX", "KC", "LV", "LAC", "LA", "MIA",
           "MIN", "NE", "NO", "NYG", "NYJ", "PHI", "PIT", "SF", "SEA", "TB",
           "TEN", "WAS"),
  lat = c(33.5276, 33.7553, 39.2780, 42.7738, 35.2258, 41.8623, 39.0954, 41.5061, 32.7473, 39.7439,
          42.3400, 44.5013, 29.6847, 39.7601, 30.3240, 39.0489, 36.0909, 33.8634, 34.0139, 25.9580,
          44.9738, 42.0909, 29.9511, 40.8128, 40.8135, 39.9008, 40.4468, 37.7699, 47.5952, 27.9759,
          36.1665, 38.9072),
  lon = c(-112.2626, -84.4009, -76.6227, -78.7870, -80.8530, -87.6167, -84.5160, -81.6995, -97.0945, -105.0201,
          -83.0456, -88.0622, -95.4107, -86.1639, -81.6373, -94.4839, -115.1836, -118.2631, -118.2878, -80.2389,
          -93.2577, -71.2643, -90.0812, -74.0742, -74.0745, -75.1675, -80.0158, -122.3860, -122.3316, -82.5033,
          -86.7713, -76.8645),
  roof = c("Retractable", "Retractable", "Open", "Open", "Open", "Open", "Open", "Open", "Retractable", "Open",
           "Dome", "Open", "Retractable", "Retractable", "Open", "Open", "Dome", "Open", "Open", "Open",
           "Dome", "Open", "Dome", "Open", "Open", "Open", "Open", "Open", "Open", "Open",
           "Open", "Open"),
  stringsAsFactors = FALSE
)

# Function to get weather forecast from Open-Meteo (free API, no key required)
get_weather_forecast <- function(lat, lon, game_date) {
  
  # Open-Meteo API endpoint
  # Note: API returns precipitation in millimeters by default
  url <- paste0(
    "https://api.open-meteo.com/v1/forecast?",
    "latitude=", lat,
    "&longitude=", lon,
    "&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max",
    "&temperature_unit=fahrenheit",
    "&wind_speed_unit=mph",
    "&timezone=America%2FNew_York"
  )
  
  tryCatch({
    response <- GET(url)
    
    if (status_code(response) != 200) {
      return(NULL)
    }
    
    data <- fromJSON(content(response, "text", encoding = "UTF-8"))
    
    # Find the forecast for game_date
    forecast_dates <- as.Date(data$daily$time)
    game_date <- as.Date(game_date)
    
    date_idx <- which(forecast_dates == game_date)
    
    if (length(date_idx) == 0) {
      return(NULL)
    }
    
    # v3 FIX: Convert precipitation from mm to inches
    # API returns mm by default, we need inches for US audience
    precip_mm <- data$daily$precipitation_sum[date_idx]
    precip_inches <- precip_mm / 25.4  # 1 inch = 25.4 mm
    
    weather <- list(
      temp_max = data$daily$temperature_2m_max[date_idx],
      temp_min = data$daily$temperature_2m_min[date_idx],
      precipitation = precip_inches,  # Now in inches
      wind_speed = data$daily$wind_speed_10m_max[date_idx]
    )
    
    return(weather)
    
  }, error = function(e) {
    return(NULL)
  })
}

# Load current predictions from appropriate file (configured in run_weekly_predictions.R)
latest_file <- Sys.getenv("LATEST_FILE", "data/predictions/latest_predictions.csv")
predictions <- read.csv(latest_file, stringsAsFactors = FALSE)

cat(paste("  Fetching weather for", nrow(predictions), "games...\n"))

# Add weather data to predictions
predictions$temp <- NA
predictions$wind_speed <- NA
predictions$precipitation <- NA
predictions$weather_impact <- 0

for (i in 1:nrow(predictions)) {
  game <- predictions[i, ]
  
  # Get home team location
  home_loc <- stadium_locations[stadium_locations$team == game$home_team, ]
  
  if (nrow(home_loc) == 0) {
    next
  }
  
  # Skip domed stadiums
  if (home_loc$roof == "Dome") {
    next
  }
  
  # Get weather forecast
  weather <- get_weather_forecast(home_loc$lat, home_loc$lon, game$game_date)
  
  if (is.null(weather)) {
    next
  }
  
  # Store weather data (precipitation now in inches)
  predictions$temp[i] <- weather$temp_max
  predictions$wind_speed[i] <- weather$wind_speed
  predictions$precipitation[i] <- weather$precipitation
  
  # Calculate weather impact on spread
  impact <- 0
  
  # Wind impact (affects passing significantly)
  if (!is.na(weather$wind_speed)) {
    if (weather$wind_speed > 20) {
      impact <- impact - 3.0  # Strong wind favors rushing, hurts passing
    } else if (weather$wind_speed > 15) {
      impact <- impact - 1.5
    } else if (weather$wind_speed > 10) {
      impact <- impact - 0.5
    }
  }
  
  # Temperature impact (extreme cold affects passing)
  if (!is.na(weather$temp_max)) {
    if (weather$temp_max < 20) {
      impact <- impact - 2.0  # Extreme cold
    } else if (weather$temp_max < 32) {
      impact <- impact - 1.0  # Freezing
    } else if (weather$temp_max > 95) {
      impact <- impact - 0.5  # Extreme heat
    }
  }
  
  # Precipitation impact (now correctly in inches)
  if (!is.na(weather$precipitation)) {
    if (weather$precipitation > 0.5) {
      impact <- impact - 2.0  # Significant rain (>0.5 inches)
    } else if (weather$precipitation > 0.1) {
      impact <- impact - 0.5  # Light rain (0.1-0.5 inches)
    }
  }
  
  # Apply weather impact (negative = favors home team in bad weather due to familiarity)
  # But if away team is pass-heavy and home team is run-heavy, adjust accordingly
  # For now, apply generic impact
  predictions$weather_impact[i] <- impact
}

# Apply weather to spread
predictions$final_spread <- predictions$spread_after_injuries + predictions$weather_impact

# CRITICAL: Recalculate win probability from FINAL spread (after both injuries AND weather)
sigma <- 13.5
predictions$final_home_win_probability <- pnorm(predictions$final_spread / sigma) * 100

# Update predicted winner based on final spread
predictions$predicted_winner <- ifelse(
  predictions$final_spread > 0,
  predictions$home_team,
  predictions$away_team
)

cat(paste("✓ Weather data integrated for", sum(!is.na(predictions$wind_speed)), "outdoor games\n"))

# Select and order final columns for better readability
final_predictions <- predictions %>%
  select(
    # TIER 1: Core Info
    game_date,
    away_team,
    home_team,
    predicted_winner,
    
    # TIER 2: Final Predictions (what you bet on)
    final_spread,
    final_home_win_probability,
    predicted_total,
    
    # TIER 3: Adjustment Breakdown
    base_spread = predicted_spread,
    spread_after_injuries,
    injury_impact,
    home_injury_impact,
    away_injury_impact,
    weather_impact,
    
    # TIER 4: Details
    home_injuries,
    away_injuries,
    base_home_win_probability = home_win_probability,
    home_win_probability_after_injuries,
    temp,
    wind_speed,
    precipitation,  # Now correctly in inches
    prediction_date
  )

# Save to appropriate file based on run type (configured in run_weekly_predictions.R)
latest_file <- Sys.getenv("LATEST_FILE", "data/predictions/latest_predictions.csv")
run_prefix <- Sys.getenv("RUN_PREFIX", "manual")

write.csv(final_predictions, latest_file, row.names = FALSE)
cat(paste("✓ Saved to", latest_file, "\n"))

# Save dated copy with run type prefix
dated_file <- paste0("data/predictions/predictions_", run_prefix, "_", Sys.Date(), ".csv")
write.csv(final_predictions, dated_file, row.names = FALSE)
cat(paste("✓ Saved dated predictions:", dated_file, "\n"))

# Show games with significant weather impact
weather_games <- final_predictions[abs(final_predictions$weather_impact) > 1, ]

if (nrow(weather_games) > 0) {
  cat("\n=== Games with Weather Impact ===\n")
  for (i in 1:nrow(weather_games)) {
    game <- weather_games[i, ]
    cat(paste0(
      game$away_team, " @ ", game$home_team,
      " | Temp: ", round(game$temp, 0), "°F",
      " | Wind: ", round(game$wind_speed, 0), " mph",
      " | Precip: ", round(game$precipitation, 2), " in",  # Now shows inches correctly
      " | Impact: ", round(game$weather_impact, 1), " pts\n"
    ))
  }
}

cat("\n=== v3 COLUMN STRUCTURE ===\n")
cat("TIER 1 - Core: game_date, away_team, home_team, predicted_winner\n")
cat("TIER 2 - Final: final_spread, final_home_win_probability, predicted_total\n")
cat("TIER 3 - Breakdown: base_spread, spread_after_injuries, injury_impact, etc.\n")
cat("TIER 4 - Details: home_injuries, away_injuries, weather (in inches), etc.\n")
cat("\n=== v3 KEY FEATURES ===\n")
cat("✓ CRITICAL FIX: Precipitation now correctly converted from mm to inches\n")
cat("✓ Win probability calculated from final_spread (includes weather)\n")
cat("✓ Clear naming: final_spread, final_home_win_probability\n")
cat("✓ Better column order: final values first, then breakdown\n")
cat("✓ All injury details preserved for analysis\n")
cat("\n✓ Weather adjustments complete\n")
