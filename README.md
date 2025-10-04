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
- **Monday at 9 AM ET**
- **Wednesday at 9 AM ET**
- **Saturday at 9 AM ET**
- **Sunday at 9 AM ET**

Manual trigger available from GitHub Actions tab.

## 📁 Project Structure

```
nflmodel2/
├── scripts/
│   ├── 00_setup.R                           # Package installation
│   ├── 01_load_data.R                       # Load 3+ seasons
│   ├── 02_calculate_features.R              # Elo + rolling stats
│   ├── 03_train_model.R                     # Train models
│   ├── 04_make_predictions.R                # Base predictions
│   ├── 05_calculate_defensive_ratings.R     # Defensive EPA
│   ├── 06_adjust_injuries_opponent_context.R # Injury adjustments
│   ├── 07_integrate_weather.R               # Weather forecasts
│   └── 08_backup_qb_performance.R           # QB performance DB
├── data/
│   ├── predictions/
│   │   ├── latest_predictions.csv           # Current (17 columns)
│   │   └── predictions_YYYY-MM-DD.csv       # Dated archive
│   ├── injury_report.csv                    # Verification checklist
│   └── [cached data files]
├── models/
│   └── nfl_models.rds
└── run_weekly_predictions.R
```

## 🔧 How It Works

### Model Components

**1. Base Model**
- Logistic regression (winner prediction)
- Linear regression (spread/total)
- Elo ratings + rolling 15-game averages

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
- Game info, teams, date
- Predicted winner and probabilities
- Base spread and injury/weather adjusted spreads
- Impact values for each adjustment
- Detailed injury list per team
- Weather conditions

**injury_report.csv:**
- All teams' injuries (OUT/DOUBTFUL/QUESTIONABLE)
- Sorted by team and position priority
- Use for manual verification before betting

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

## ⚙️ Enhancements

✅ Opponent-adjusted defensive ratings  
✅ QB-specific injury impact  
✅ Weather integration  
✅ Backup QB performance database  
✅ ESPN depth chart integration  
✅ Injury report export  
✅ Automated GitHub Actions  

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

## 📚 Model Validation

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