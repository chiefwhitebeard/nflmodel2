# NFL Predictions Model - Unit Tests
# Run with: Rscript tests/run_tests.R

suppressPackageStartupMessages({
  library(testthat)
})

# Ensure we're in the project root
test_root <- getwd()
if (basename(test_root) == "tests") {
  setwd("..")
}

cat("Running NFL Prediction Model Tests...\n")
cat(paste("Test working directory:", getwd(), "\n\n"))

# Test 1: Check that required data files exist
test_that("Required data files exist after pipeline run", {
  expect_true(file.exists("data/raw_game_data.rds"),
              info = "raw_game_data.rds should exist")
  expect_true(file.exists("data/features_data.rds"),
              info = "features_data.rds should exist")
  expect_true(file.exists("models/nfl_models.rds"),
              info = "nfl_models.rds should exist")
  expect_true(file.exists("data/predictions/latest_predictions.csv"),
              info = "latest_predictions.csv should exist")
})

# Test 2: Validate prediction file structure
test_that("Predictions file has required columns", {
  if (!file.exists("data/predictions/latest_predictions.csv")) {
    skip("No predictions file found")
  }

  predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

  required_cols <- c(
    "game_date", "away_team", "home_team", "predicted_winner",
    "final_spread", "final_home_win_probability", "predicted_total",
    "base_spread", "spread_after_injuries", "injury_impact",
    "home_injury_impact", "away_injury_impact", "weather_impact"
  )

  for (col in required_cols) {
    expect_true(col %in% names(predictions),
                info = paste("Column", col, "should exist in predictions"))
  }
})

# Test 3: Validate prediction value ranges
test_that("Prediction values are within valid ranges", {
  if (!file.exists("data/predictions/latest_predictions.csv")) {
    skip("No predictions file found")
  }

  predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

  # Win probabilities should be 0-100
  expect_true(all(predictions$final_home_win_probability >= 0 &
                  predictions$final_home_win_probability <= 100),
              info = "Win probabilities should be between 0-100")

  # Spreads should be reasonable (typically -30 to +30)
  expect_true(all(abs(predictions$final_spread) <= 50),
              info = "Spreads should be within reasonable bounds")

  # Totals should be reasonable (typically 30-70 points)
  expect_true(all(predictions$predicted_total >= 20 &
                  predictions$predicted_total <= 80),
              info = "Predicted totals should be realistic")

  # Weather impact should be reasonable (typically -5 to 0)
  expect_true(all(abs(predictions$weather_impact) <= 10),
              info = "Weather impact should be reasonable")
})

# Test 4: Validate team abbreviations
test_that("Team abbreviations are valid NFL teams", {
  if (!file.exists("data/predictions/latest_predictions.csv")) {
    skip("No predictions file found")
  }

  predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

  valid_teams <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE",
                   "DAL", "DEN", "DET", "GB", "HOU", "IND", "JAX", "KC",
                   "LV", "LAC", "LA", "MIA", "MIN", "NE", "NO", "NYG",
                   "NYJ", "PHI", "PIT", "SF", "SEA", "TB", "TEN", "WAS")

  expect_true(all(predictions$home_team %in% valid_teams),
              info = "All home teams should be valid NFL teams")
  expect_true(all(predictions$away_team %in% valid_teams),
              info = "All away teams should be valid NFL teams")
})

# Test 5: Check model object structure
test_that("Trained models have required components", {
  if (!file.exists("models/nfl_models.rds")) {
    skip("No models file found")
  }

  models <- readRDS("models/nfl_models.rds")

  expect_true("winner" %in% names(models),
              info = "Winner model should exist")
  expect_true("spread" %in% names(models),
              info = "Spread model should exist")
  expect_true("total" %in% names(models),
              info = "Total model should exist")
  expect_true("accuracy" %in% names(models),
              info = "Accuracy metric should exist")
})

# Test 6: Validate Elo probability conversion
test_that("Spread to probability conversion is correct", {
  # Test the sigma = 13.5 conversion used in weather script
  sigma <- 13.5

  # Home favored by 13.5 should be ~84% (1 sigma)
  prob_1sigma <- pnorm(13.5 / sigma) * 100
  expect_true(prob_1sigma > 83 && prob_1sigma < 85,
              info = "13.5 point favorite should be ~84% likely to win")

  # Even matchup (0 spread) should be 50%
  prob_even <- pnorm(0 / sigma) * 100
  expect_equal(prob_even, 50,
              info = "0 point spread should be 50% win probability")

  # Underdog by 13.5 should be ~16%
  prob_underdog <- pnorm(-13.5 / sigma) * 100
  expect_true(prob_underdog > 15 && prob_underdog < 17,
              info = "13.5 point underdog should be ~16% likely to win")
})

# Test 7: Validate adjustment logic integrity
test_that("Spread adjustments are applied correctly", {
  if (!file.exists("data/predictions/latest_predictions.csv")) {
    skip("No predictions file found")
  }

  predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

  # Check that final_spread = spread_after_injuries + weather_impact
  calculated_final <- predictions$spread_after_injuries + predictions$weather_impact
  expect_equal(predictions$final_spread, calculated_final,
              info = "final_spread should equal spread_after_injuries + weather_impact")

  # Check that spread_after_injuries = base_spread + injury_impact
  calculated_injury <- predictions$base_spread + predictions$injury_impact
  expect_equal(predictions$spread_after_injuries, calculated_injury,
              info = "spread_after_injuries should equal base_spread + injury_impact")
})

# Test 8: Check prediction dates are current
test_that("Predictions are recent and dated correctly", {
  if (!file.exists("data/predictions/latest_predictions.csv")) {
    skip("No predictions file found")
  }

  predictions <- read.csv("data/predictions/latest_predictions.csv", stringsAsFactors = FALSE)

  # Game dates should be in the future or very recent past
  game_dates <- as.Date(predictions$game_date)
  expect_true(all(game_dates >= Sys.Date() - 14),
              info = "Game dates should not be more than 2 weeks old")

  # Prediction date should be recent
  pred_date <- as.Date(predictions$prediction_date[1])
  expect_true(pred_date >= Sys.Date() - 7,
              info = "Predictions should be generated within last week")
})

# Summary
cat("\n=== Test Summary ===\n")
cat("All tests completed. Check output above for any failures.\n")
