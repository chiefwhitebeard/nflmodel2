# Error Handling Utilities
# Centralized error handling functions for the NFL prediction pipeline
# Use: source("scripts/00_error_handling.R") at the start of any script

suppressPackageStartupMessages({
  library(dplyr)
})

# Initialize error log
ERROR_LOG_FILE <- "data/error_log.csv"

# Initialize error log if it doesn't exist
initialize_error_log <- function() {
  if (!file.exists(ERROR_LOG_FILE)) {
    if (!dir.exists("data")) {
      dir.create("data", recursive = TRUE)
    }
    log_df <- data.frame(
      timestamp = character(),
      script = character(),
      error_type = character(),
      error_message = character(),
      run_type = character(),
      stringsAsFactors = FALSE
    )
    write.csv(log_df, ERROR_LOG_FILE, row.names = FALSE)
  }
}

# Log an error to CSV
log_error <- function(script_name, error_type, error_message, run_type = "unknown") {
  tryCatch({
    initialize_error_log()

    new_entry <- data.frame(
      timestamp = as.character(Sys.time()),
      script = script_name,
      error_type = error_type,
      error_message = substr(as.character(error_message), 1, 500),  # Truncate long messages
      run_type = run_type,
      stringsAsFactors = FALSE
    )

    existing_log <- read.csv(ERROR_LOG_FILE, stringsAsFactors = FALSE)
    updated_log <- rbind(existing_log, new_entry)
    write.csv(updated_log, ERROR_LOG_FILE, row.names = FALSE)
  }, error = function(e) {
    # If logging fails, at least print to console
    cat(paste("⚠️  Failed to log error:", e$message, "\n"))
  })
}

# Safe file read with validation
safe_read_csv <- function(file_path, required_columns = NULL, script_name = "unknown") {
  tryCatch({
    if (!file.exists(file_path)) {
      stop(paste("File not found:", file_path))
    }

    data <- read.csv(file_path, stringsAsFactors = FALSE)

    if (nrow(data) == 0) {
      warning(paste("File is empty:", file_path))
    }

    # Validate required columns
    if (!is.null(required_columns)) {
      missing_cols <- setdiff(required_columns, names(data))
      if (length(missing_cols) > 0) {
        stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
      }
    }

    return(data)

  }, error = function(e) {
    log_error(script_name, "FILE_READ_ERROR",
              paste("Failed to read", file_path, ":", e$message),
              Sys.getenv("RUN_TYPE", "unknown"))
    stop(e$message)
  })
}

# Safe file write with backup
safe_write_csv <- function(data, file_path, script_name = "unknown", backup = TRUE) {
  tryCatch({
    # Validate data isn't empty
    if (nrow(data) == 0) {
      warning(paste("Writing empty data frame to", file_path))
    }

    # Create backup if file exists
    if (backup && file.exists(file_path)) {
      backup_path <- paste0(file_path, ".backup")
      file.copy(file_path, backup_path, overwrite = TRUE)
    }

    write.csv(data, file_path, row.names = FALSE)

    # Remove backup on success
    if (backup && file.exists(paste0(file_path, ".backup"))) {
      file.remove(paste0(file_path, ".backup"))
    }

    return(TRUE)

  }, error = function(e) {
    log_error(script_name, "FILE_WRITE_ERROR",
              paste("Failed to write", file_path, ":", e$message),
              Sys.getenv("RUN_TYPE", "unknown"))

    # Restore backup if write failed
    backup_path <- paste0(file_path, ".backup")
    if (backup && file.exists(backup_path)) {
      file.copy(backup_path, file_path, overwrite = TRUE)
      cat(paste("✓ Restored backup after write failure:", file_path, "\n"))
    }

    stop(e$message)
  })
}

# Safe network call with retries and exponential backoff
safe_network_call <- function(func, max_retries = 3, initial_delay = 2,
                              script_name = "unknown", operation = "network operation") {

  for (attempt in 1:max_retries) {
    result <- tryCatch({
      func()
    }, error = function(e) {
      if (attempt < max_retries) {
        delay <- initial_delay * (2 ^ (attempt - 1))  # Exponential backoff: 2s, 4s, 8s
        cat(paste("⚠️ ", operation, "failed (attempt", attempt, "of", max_retries, "):", e$message, "\n"))
        cat(paste("  Retrying in", delay, "seconds...\n"))
        Sys.sleep(delay)
        return(NULL)
      } else {
        log_error(script_name, "NETWORK_ERROR",
                 paste(operation, "failed after", max_retries, "attempts:", e$message),
                 Sys.getenv("RUN_TYPE", "unknown"))
        cat(paste("✗", operation, "failed after", max_retries, "attempts\n"))
        return(NULL)
      }
    })

    if (!is.null(result)) {
      if (attempt > 1) {
        cat(paste("✓", operation, "succeeded on attempt", attempt, "\n"))
      }
      return(result)
    }
  }

  return(NULL)
}

# Validate prediction data structure
validate_predictions <- function(predictions, script_name = "unknown", stage = "unknown") {
  required_cols <- c("game_date", "away_team", "home_team", "predicted_winner",
                     "predicted_spread", "predicted_total")

  missing_cols <- setdiff(required_cols, names(predictions))

  if (length(missing_cols) > 0) {
    error_msg <- paste("Predictions at stage", stage, "missing required columns:",
                      paste(missing_cols, collapse = ", "))
    log_error(script_name, "DATA_VALIDATION_ERROR", error_msg,
             Sys.getenv("RUN_TYPE", "unknown"))
    stop(error_msg)
  }

  # Check for NA values in critical columns
  critical_cols <- c("predicted_spread", "predicted_total", "predicted_winner")
  for (col in critical_cols) {
    if (col %in% names(predictions)) {
      na_count <- sum(is.na(predictions[[col]]))
      if (na_count > 0) {
        warning(paste("Column", col, "at stage", stage, "has", na_count, "NA values"))
      }
    }
  }

  # Validate we have some games
  if (nrow(predictions) == 0) {
    error_msg <- paste("Predictions at stage", stage, "has no games")
    log_error(script_name, "DATA_VALIDATION_ERROR", error_msg,
             Sys.getenv("RUN_TYPE", "unknown"))
    stop(error_msg)
  }

  return(TRUE)
}

# Execute script step with error handling
safe_execute_step <- function(step_number, step_name, script_path,
                               required = TRUE, run_type = "unknown") {
  cat(paste("STEP", step_number, ":", step_name, "...\n"))

  result <- tryCatch({
    source(script_path, local = FALSE)
    cat(paste("✓ Step", step_number, "complete\n\n"))
    return(TRUE)

  }, error = function(e) {
    error_msg <- paste("Step", step_number, "failed:", e$message)
    cat(paste("✗", error_msg, "\n\n"))

    log_error(basename(script_path), "PIPELINE_ERROR", error_msg, run_type)

    if (required) {
      stop(paste("Critical step failed:", step_name))
    } else {
      cat(paste("⚠️  Non-critical step failed, continuing with degraded predictions...\n\n"))
      return(FALSE)
    }
  })

  return(result)
}

# Create summary of recent errors
get_error_summary <- function(since_hours = 24) {
  if (!file.exists(ERROR_LOG_FILE)) {
    return("No errors logged.")
  }

  tryCatch({
    errors <- read.csv(ERROR_LOG_FILE, stringsAsFactors = FALSE)

    if (nrow(errors) == 0) {
      return("No errors logged.")
    }

    errors$timestamp <- as.POSIXct(errors$timestamp)

    recent_errors <- errors[errors$timestamp > (Sys.time() - since_hours * 3600), ]

    if (nrow(recent_errors) == 0) {
      return(paste("No errors in last", since_hours, "hours."))
    }

    summary <- paste0(
      "Errors in last ", since_hours, " hours: ", nrow(recent_errors), "\n",
      "By type:\n"
    )

    error_counts <- table(recent_errors$error_type)
    for (type in names(error_counts)) {
      summary <- paste0(summary, "  - ", type, ": ", error_counts[[type]], "\n")
    }

    return(summary)

  }, error = function(e) {
    return(paste("Failed to generate error summary:", e$message))
  })
}

cat("✓ Error handling utilities loaded\n")
