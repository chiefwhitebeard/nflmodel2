# NFL Predictions Model - Weather Integration
# This script fetches weather forecasts and adjusts predictions accordingly

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(lubridate)
})

cat("Integrating weather data...\n")

# Load historical data for cover probability calculations
features_data <- readRDS("data/features_data.rds")

# Function to calculate cover probability using spread uncertainty
calculate_cover_probability <- function(predicted_spread) {
  sigma <- 10.0  # NFL spread uncertainty
  cover_prob <- pnorm(0, mean = predicted_spread, sd = sigma, lower.tail = FALSE) * 100
  return(round(cover_prob, 1))
}

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
    
    weather <- list(
      temp_max = data$daily$temperature_2m_max[date_idx],
      temp_min = data$daily$temperature_2m_min[date_idx],
      precipitation = data$daily$precipitation_sum[date_idx],
      wind_speed = data$daily$wind_speed_10m_max[date_idx]
    )
    
    return(weather)
    
  }, error = function(e) {
    return(NULL)
  })
}

# Load current predictions
predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

cat("\n=== DEBUG: Columns after loading CSV ===\n")
print(names(predictions))

cat(paste("  Fetching weather for", nrow(predictions), "games...\n"))

# Initialize weather columns only if they don't exist (preserve existing values)
if (!("temp" %in% names(predictions))) predictions$temp <- NA
if (!("wind_speed" %in% names(predictions))) predictions$wind_speed <- NA
if (!("precipitation" %in% names(predictions))) predictions$precipitation <- NA
if (!("weather_impact" %in% names(predictions))) predictions$weather_impact <- 0

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
  
  # Store weather data
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
  
  # Precipitation impact
  if (!is.na(weather$precipitation)) {
    if (weather$precipitation > 0.5) {
      impact <- impact - 2.0  # Significant rain
    } else if (weather$precipitation > 0.1) {
      impact <- impact - 0.5  # Light rain
    }
  }
  
  # Apply weather impact (negative = favors home team in bad weather due to familiarity)
  predictions$weather_impact[i] <- impact
}

# Adjust spread based on weather
predictions$predicted_spread_weather_adjusted <- 
  predictions$predicted_spread_injury_adjusted + predictions$weather_impact

# NEW: Calculate cover probability for weather-adjusted spread
predictions$cover_probability_weather_adjusted <- sapply(
  predictions$predicted_spread_weather_adjusted,
  calculate_cover_probability
)

# NEW: Set final adjusted values (cumulative of all adjustments)
predictions$adjusted_spread <- predictions$predicted_spread_weather_adjusted
predictions$adjusted_cover_probability <- predictions$cover_probability_weather_adjusted

cat(paste("✓ Weather data integrated for", sum(!is.na(predictions$wind_speed)), "outdoor games\n"))

cat("\n=== DEBUG: Columns before saving CSV ===\n")
print(names(predictions))

# Save updated predictions
write.csv(predictions, "data/predictions/latest_predictions.csv", row.names = FALSE)

# Also save as latest_tracking if this is a tracking run
if (Sys.getenv("RUN_TYPE") == "tracking") {
  write.csv(predictions, "data/predictions/latest_tracking.csv", row.names = FALSE)
  cat("✓ Also saved as latest_tracking.csv\n")
}

# Save dated copy with identical structure
dated_file <- paste0("data/predictions/predictions_", Sys.Date(), ".csv")
write.csv(predictions, dated_file, row.names = FALSE)
cat(paste("✓ Saved dated predictions:", dated_file, "\n"))

# Show games with significant weather impact
weather_games <- predictions[abs(predictions$weather_impact) > 1, ]

if (nrow(weather_games) > 0) {
  cat("\n=== Games with Weather Impact ===\n")
  for (i in 1:nrow(weather_games)) {
    game <- weather_games[i, ]
    cat(paste0(
      game$away_team, " @ ", game$home_team,
      " | Temp: ", round(game$temp, 0), "°F",
      " | Wind: ", round(game$wind_speed, 0), " mph",
      " | Precip: ", round(game$precipitation, 2), " in",
      " | Spread: ", round(game$predicted_spread_injury_adjusted, 1),
      " → ", round(game$adjusted_spread, 1),
      " | Cover %: ", game$cover_probability_injury_adjusted,
      "% → ", game$adjusted_cover_probability, "%\n"
    ))
  }
}

cat("\n✓ Weather adjustments complete\n")
cat("\n=== FINAL PREDICTIONS SUMMARY ===\n")
summary_display <- predictions %>%
  mutate(game = paste0(away_team, " @ ", home_team)) %>%
  select(game, final_spread = adjusted_spread, cover_prob = adjusted_cover_probability)
print(summary_display, row.names = FALSE)