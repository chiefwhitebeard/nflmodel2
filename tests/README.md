# NFL Prediction Model Tests

## Running Tests

### Run all tests:
```r
Rscript tests/run_tests.R
```

### Run specific test file:
```r
Rscript tests/test_predictions.R
```

### From R console:
```r
library(testthat)
test_dir("tests")
```

## What's Tested

1. **File Existence** - Verifies all required data files exist after pipeline runs
2. **Column Structure** - Ensures prediction output has all required columns
3. **Value Ranges** - Validates probabilities (0-100%), spreads, and totals are realistic
4. **Team Codes** - Checks all team abbreviations are valid NFL teams
5. **Model Components** - Verifies trained model objects have required parts
6. **Probability Math** - Tests spread-to-probability conversion formula
7. **Adjustment Logic** - Validates injury and weather adjustments sum correctly
8. **Date Validity** - Ensures predictions are current and game dates are reasonable

## When to Run Tests

- **After full pipeline run** - To verify everything generated correctly
- **Before committing changes** - To catch regressions
- **After modifying features** - To ensure calculations still work
- **Weekly** - As part of prediction generation workflow

## Expected Test Time

~5-10 seconds (fast, no heavy computation)

## Dependencies

- `testthat` package (auto-installed if missing)
- Requires at least one prediction run to have completed
