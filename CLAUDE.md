# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an automated NFL game prediction system built in R for sports betting analysis. It uses nflfastR data, EPA-based features, Elo ratings, and injury/weather adjustments to predict game outcomes, spreads, and totals. The model tracks sharp market efficiency and typically aligns within 0.3-0.5 points of professional lines.

**Philosophy**: The model is designed for disciplined betting. Most predictions should show minimal edge vs. market (this is correct). Frequent large disagreements likely indicate model error, not market inefficiency.

## Running the Model

### Manual Prediction Generation
```bash
cd ~/Desktop/nflmodel2
Rscript run_weekly_predictions.R
```
Runtime: ~25-45 seconds

**CRITICAL**: Never run during active games. Live data corrupts defensive EPA calculations.

### Automated Runs
GitHub Actions runs automatically:
- Tuesday 6 AM ET (primary run)
- Can be manually triggered from Actions tab

Local sync after automated run:
```bash
git pull
```

### Package Installation (one-time setup)
```r
source("scripts/00_setup.R")
```

## Architecture

### Prediction Pipeline Sequence

The system runs 8 sequential scripts orchestrated by `run_weekly_predictions.R`:

1. **01_load_data.R** - Loads 3+ seasons of NFL schedule/results from nflreadr
2. **02_calculate_features.R** - Calculates Elo ratings, rolling averages, EPA metrics, rest differentials
3. **03_train_model.R** - Trains 3 models (winner, spread, total) using logistic/linear regression
4. **04_make_predictions.R** - Generates base predictions for current week
5. **05_calculate_defensive_ratings.R** - Calculates defensive EPA by position (pass/rush)
6. **08_backup_qb_performance.R** - Builds QB performance database from historical EPA
7. **06_adjust_injuries_opponent_context.R** - Adjusts predictions using opponent-specific defensive ratings and QB replacements
8. **07_integrate_weather.R** - Fetches forecasts from Open-Meteo API and applies weather impact

Each script loads the output of previous steps and updates `data/predictions/latest_predictions.csv` progressively.

### Key Data Flow

**Training Phase (scripts 1-3)**:
- Raw games → Features with Elo + EPA + rolling stats → Trained models saved to `models/nfl_models.rds`

**Prediction Phase (scripts 4-8)**:
- Base predictions → Injury adjustments (opponent-aware) → Weather adjustments → Final predictions

**Critical intermediate data**:
- `data/raw_game_data.rds` - Historical game results
- `data/features_data.rds` - Training features with Elo, EPA, rolling stats
- `data/defense_ratings.rds` - Position-specific defensive EPA
- `data/qb_performance.rds` - Historical QB performance for backup impact
- `models/nfl_models.rds` - Trained prediction models

### Feature Engineering (02_calculate_features.R)

Core features calculated per team:
- **Elo ratings** (initial=1500, k=20) with pre/post game values
- **Rolling averages** (10-game window): points for/against, win percentage
- **Recent form** (3-game weighted): 1.0x, 1.5x, 2.0x for last 3 games
- **EPA metrics** from play-by-play: offensive EPA/play, success rate, pass/rush EPA
- **Defensive EPA**: EPA allowed per play on defense
- **Rest differential**: Days since last game for each team
- **Divisional games**: Binary flag for division matchups

All rolling stats shifted by 1 game to prevent look-ahead bias.

### Injury Adjustment Logic (06_adjust_injuries_opponent_context.R)

**Position Impact Weights**:
- QB: 10.0 (starter), calculated from historical EPA differential vs backup
- OL: 2.5
- WR: 2.0
- RB: 1.5
- TE: 1.5
- Other: 0.5

**Opponent Context**:
- QB injuries weighted by opponent defensive pass EPA
- Skill position injuries weighted by opponent defensive rush/pass EPA
- OL injuries weighted by opponent overall defensive EPA

**QB Replacement Logic**:
- Requires 50+ attempts in last 3 weeks to count as "active" QB
- Compares starter EPA to backup EPA from `data/qb_performance.rds`
- Impact capped at -10 to -2 points per QB
- If no historical data, defaults to -5 point penalty

**Status Severity**:
- OUT/IR: 100% impact
- DOUBTFUL: 75% impact
- QUESTIONABLE: 0% impact (usually plays)

Injury data fetched from ESPN API, supplemented with nflreadr roster data for IR.

### Weather Adjustment (07_integrate_weather.R)

**Data Source**: Open-Meteo API (free, no key required)

**Conditions Affecting Predictions**:
- Wind > 15 mph: Reduces predicted total by 1-3 points (scaled linearly)
- Temperature < 32°F: Reduces predicted total by 1-2 points
- Precipitation > 0.1 inches: Reduces predicted total by 1 point

**Important**: Only applies to outdoor stadiums. Domed/retractable roofs excluded.

Weather impact accumulates with injury impact in final spread/total adjustments.

## Output Files

### Primary Output: data/predictions/latest_predictions.csv

17 columns:
- `game_date`, `away_team`, `home_team`
- `predicted_winner`, `predicted_spread`, `predicted_total`
- `home_win_probability` (base and injury-adjusted versions)
- `predicted_spread_injury_adjusted`, `predicted_spread_weather_adjusted`
- `adjusted_spread` (final cumulative value)
- `cover_probability` variants (base, injury-adjusted, weather-adjusted, final)
- `injury_impact`, `weather_impact` (point adjustments)
- `temp`, `wind_speed`, `precipitation`
- `prediction_date`

### Secondary Output: data/injury_report.csv

Sorted injury list by team and position priority (QB → OL → skill positions). Used for manual verification before betting.

### Archived Predictions

Dated files created at end of each run:
- Manual: `predictions_manual_YYYY-MM-DD.csv`
- Automated: `predictions_primary_YYYY-MM-DD.csv` or `predictions_tracking_YYYY-MM-DD.csv`

## Model Characteristics

**Performance Targets**:
- Winner accuracy: ~68-70%
- Spread MAE: ~8-10 points
- Total MAE: ~10-12 points
- Market alignment: Within 0.3-0.5 points of sharp lines

**Probability Capping**:
- Win probabilities capped at 5-95% to acknowledge NFL uncertainty
- No game is truly 100% or 0%

**Spread → Win Probability Conversion**:
Uses normal distribution with sigma=13.5 points:
```r
win_prob = pnorm(predicted_spread / 13.5)
```

## Betting Analysis Workflow

1. Review `latest_predictions.csv` for weekly predictions
2. Check `injury_report.csv` to verify injury assumptions (ESPN API can be stale)
3. Compare model spread vs market odds
4. Investigate 3+ point discrepancies (model may be wrong, or market may be inefficient)
5. **Manually verify QB starters** before betting (depth charts change)
6. Calculate Kelly stake for +EV opportunities only

**Market Weighting Recommendation**: 75% market / 25% model
- 0.3 point gap = no edge
- 3+ point gap = worth investigating
- 5+ point gap = likely stale info or model error

## Important Limitations

**Injury Data**:
- ESPN API can timeout or have stale data
- Always manually verify QB starters before betting
- Official Friday injury reports are authoritative

**Timing**:
- Don't run during active games (corrupts defensive EPA calculations)
- Model is static snapshot; market lines move throughout week
- Cannot predict surprise game-day inactives

**Model Scope**:
- Does NOT include: coaching changes, locker room issues, motivation factors, line movement analysis
- Assumes injuries are primary information asymmetry
- Divisions and rest differentials included but not heavily weighted

## Data Sources

- **NFL Data**: nflreadr package (official NFL play-by-play via nflfastR)
- **Injuries**: ESPN Injury API + nflreadr roster data
- **Weather**: Open-Meteo API (free tier)
- **Depth Charts**: ESPN Depth Chart API

## Common Issues

**ESPN API timeout**:
- Warning displayed in pipeline output
- Falls back to base predictions without injury adjustment
- Rerun script to retry connection

**Unexpected spread shifts**:
- Check if ran during active games
- Verify injury report vs official reports
- Compare dated prediction files to see what changed

**No predictions generated**:
- Usually means insufficient historical data for team
- Check that 3+ seasons loaded successfully in step 1

## Project Structure Notes

- `scripts/` contains numbered pipeline steps (00-11)
- `data/` holds cached data and predictions subdirectory
- `models/` contains trained model objects
- Diagnostic scripts (`diag_*.R`, `check_*.R`) are for ad-hoc analysis only
- `scripts/09_recent_form.R` is commented out in main pipeline (experimental)
- `scripts/10_validate_predictions.R` and `scripts/11_accuracy_dashboard.R` are for post-game analysis

## Development Notes

**When modifying features**:
- Update both training (02_calculate_features.R, 03_train_model.R) and prediction (04_make_predictions.R) code
- Ensure feature names match exactly between training and prediction
- All rolling stats must be shifted to avoid look-ahead bias

**When adding adjustments**:
- Follow the pattern of injury/weather scripts
- Load `latest_predictions.csv`, modify columns, overwrite file
- Add new columns to output schema if needed

**Testing changes**:
```r
# Run full pipeline
source("run_weekly_predictions.R")

# Or run individual scripts after loading dependencies
source("scripts/02_calculate_features.R")
```

**Model retraining**:
Models retrain automatically on each run using last 3+ seasons minus most recent 4 weeks (held out for validation).
