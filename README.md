# NFL Predictions Model

An automated NFL game prediction system built with R and nflfastR data, designed for sports betting analysis with Kelly criterion methodology.

## 📋 What This Predicts

For the current week's games:
- **Game Winners** with win probability
- **Point Spreads** (injury and weather adjusted)
- **Total Points** (over/under)

## 🎯 Model Performance

**Current Accuracy:**
- Winner Prediction: 68.8%
- Spread MAE: 8.95 points
- Total MAE: 10.9 points
- **Market Alignment: Within 0.3-0.5 points of sharp lines**

## 🤖 Automation

Runs automatically via GitHub Actions:
- **Wednesday at 6 AM ET** (primary prediction run)

Manual trigger available from GitHub Actions tab with run type options (primary/tracking/manual).

**Continuous Testing:**
- Tests run automatically on every push to main
- Validates predictions structure and value ranges
- 34 unit tests covering data integrity and calculations

## 📁 Project Structure

```
nflmodel2/
├── scripts/
│   ├── 00_setup.R                           # Package installation
│   ├── 01_load_data.R                       # Load 3+ seasons
│   ├── 02_calculate_features.R              # Elo + rolling stats + EPA
│   ├── 03_train_model.R                     # Train models
│   ├── 04_make_predictions.R                # Base predictions
│   ├── 05_calculate_defensive_ratings.R     # Defensive EPA by position
│   ├── 08_backup_qb_performance.R           # QB performance DB (runs before 06)
│   ├── 06_adjust_injuries_opponent_context.R # Injury adjustments
│   ├── 07_integrate_weather.R               # Weather forecasts
│   ├── 10_validate_predictions.R            # Post-game validation
│   └── 11_accuracy_dashboard.R              # Performance tracking
├── data/
│   ├── predictions/
│   │   ├── latest_predictions.csv           # Current predictions (17 columns)
│   │   └── predictions_YYYY-MM-DD.csv       # Dated archives
│   ├── validation/
│   │   ├── validation_detail_YYYY-MM-DD.csv # Detailed validation results
│   │   └── accuracy_log.csv                 # Historical accuracy tracking
│   ├── injury_report.csv                    # Verification checklist
│   └── [cached .rds data files]
├── models/
│   └── nfl_models.rds                       # Trained prediction models
├── tests/
│   ├── test_predictions.R                   # 34 unit tests
│   ├── run_tests.R                          # Test runner
│   └── README.md                            # Testing documentation
├── .github/workflows/
│   ├── predictions.yml                      # Weekly prediction automation
│   └── tests.yml                            # Continuous testing
├── CLAUDE.md                                # AI assistant documentation
└── run_weekly_predictions.R                 # Master pipeline script
```

## 🔧 How It Works

### Model Components

**1. Base Model**
- Logistic regression (winner prediction)
- Linear regression (spread/total)
- Elo ratings (initial=1500, k=20) + rolling 10-game averages + 3-game weighted recent form
- EPA metrics from play-by-play data
- Rest differentials and divisional game flags

**2. Opponent-Adjusted Injuries**
- Defensive EPA by position (pass/rush)
- QB-specific impact using historical EPA
- Position-weighted impact (QB > OL > skill)
- Adjusts based on opponent strength

**3. QB Performance Database**
- Historical EPA for all QBs (50+ attempts)
- Starter vs backup performance differential
- ESPN depth chart integration
- Impact capped at -10 to -2 points

**4. Weather Integration**
- Wind, temperature, precipitation
- Only applies to outdoor stadiums
- Affects passing game predictions

### Output Files

**latest_predictions.csv (17 columns):**
- **Core Info**: game_date, away_team, home_team, predicted_winner
- **Predictions**: predicted_spread, predicted_total, home_win_probability
- **Adjusted Values**: predicted_spread_injury_adjusted, predicted_spread_weather_adjusted, adjusted_spread (final)
- **Probabilities**: cover_probability variants (base, injury-adjusted, weather-adjusted, final)
- **Impact Metrics**: injury_impact, weather_impact
- **Weather Data**: temp, wind_speed, precipitation
- **Metadata**: prediction_date

**injury_report.csv:**
- All teams' injuries (OUT/DOUBTFUL/QUESTIONABLE)
- Sorted by team and position priority
- Use for manual verification before betting

**validation_detail_YYYY-MM-DD.csv:**
- All prediction columns + actual game results
- Includes: actual_spread, actual_total, winner_correct, spread_error
- Generated after games complete for accuracy tracking

## 🚀 Usage

### Automated (Recommended)
Predictions update automatically. Sync to local:

```bash
cd ~/Desktop/nflmodel2
git pull
```

### Manual Run
```r
setwd("~/Desktop/nflmodel2")
source("run_weekly_predictions.R")
```

Runtime: ~25-45 seconds

**⚠️ CRITICAL: Never run during active games.** Live data corrupts defensive EPA calculations.

## 📊 For Betting Analysis

**Model Philosophy:**
- Tracks sharp market efficiency
- Identifies potential inefficiencies at 3+ point disagreements
- Most predictions show minimal edge (this is correct)

**Workflow:**
1. Review latest_predictions.csv
2. Check injury_report.csv to verify assumptions
3. Compare model vs market odds
4. Investigate 3+ point discrepancies
5. Manually verify QB starters before betting
6. Calculate Kelly stake for +EV opportunities only

**At 75% market / 25% model weighting:**
- 0.3 point gap = no actionable edge
- 3+ point gap = worth investigating
- 5+ point gap = potential inefficiency or stale info

## 📥 Google Sheets Integration

```
=IMPORTDATA("https://raw.githubusercontent.com/chiefwhitebeard/nflmodel2/main/data/predictions/latest_predictions.csv")
```

## ⚙️ Features

✅ Opponent-adjusted defensive ratings
✅ QB-specific injury impact
✅ Weather integration (Open-Meteo API)
✅ Backup QB performance database
✅ ESPN depth chart integration
✅ Injury report export
✅ Automated GitHub Actions
✅ Post-game validation system
✅ Unit test suite (34 tests)
✅ Continuous testing workflow
✅ CLAUDE.md AI assistant documentation  

## 🔍 Data Sources

- **NFL Data**: nflreadr (official play-by-play)
- **Injuries**: ESPN Injury API
- **Weather**: Open-Meteo API (free)
- **Depth Charts**: ESPN Depth Chart API

## ⚠️ Important Limitations

**Injury Data:**
- ESPN API can timeout or have stale data
- Always manually verify QB starters before betting
- Check official Friday injury reports

**Timing:**
- Don't run during active games
- Market lines move throughout week
- Model is static; market is dynamic

**Model Scope:**
- Does not include: coaching changes, locker room issues, motivation factors, line movement analysis
- Assumes injuries are primary information asymmetry
- Cannot predict surprise game-day inactives

## 📝 Betting Discipline

This model keeps you disciplined by mostly saying "no bet":

- Most weeks: 0-2 actionable opportunities
- 1-2 point differences = noise, not edge
- Half-Kelly recommended for bankroll preservation
- Track performance over 100+ bets
- Single game outcomes are statistically meaningless

## 🐛 Troubleshooting

**ESPN API timeout:**
- Warning displayed in output
- Uses base predictions only
- Rerun to retry connection

**Unexpected spread shifts:**
- Check if ran during active games
- Verify injury report vs official reports
- Compare dated files to see changes

**GitHub Actions failure:**
- Check Actions tab for logs
- Usually: ESPN timeouts or rate limits
- Retries on next scheduled run

## 📚 Model Validation & Testing

### Post-Game Validation
```r
Rscript scripts/10_validate_predictions.R
```

Validates predictions against actual results:
- Record: X-Y out of Z games
- Winner accuracy percentage
- Spread and total MAE
- Model bias detection
- Adjustment impact analysis

Results saved to `data/validation/` for historical tracking.

### Unit Tests
```bash
# Run test suite
Rscript tests/run_tests.R

# Or from R console
library(testthat)
test_dir("tests")
```

**34 tests covering:**
- Data file existence and structure
- Prediction column validation
- Value range checks (probabilities, spreads, totals)
- Team abbreviation validation
- Model object structure
- Probability conversion math
- Adjustment logic integrity
- Prediction date validity

Tests run automatically on every push via GitHub Actions.

### Market Alignment

Model tracking market within 0.3 points means:
- Math is correct
- Features are sound
- You understand NFL at sharp level
- Frequent +EV spots unlikely (markets efficient)

This is success. A model that significantly disagrees with sharp markets is usually wrong, not finding edge.

---

**Repository:** github.com/chiefwhitebeard/nflmodel2  
**Created:** October 2025  
**Purpose:** Disciplined sports betting analysis with Kelly criterion