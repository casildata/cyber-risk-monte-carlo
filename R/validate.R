# Checks on the hand-edited assumption files, so a typo stops the run with a
# clear message instead of producing a plausible-looking wrong answer.

validate_inputs <- function(scenarios, controls = NULL) {
  problems <- character(0)
  need <- function(df, cols, file) {
    missing <- setdiff(cols, names(df))
    if (length(missing)) {
      problems <<- c(problems, paste0(file, ": missing column(s) ", paste(missing, collapse = ", ")))
    }
    length(missing) == 0
  }
  check <- function(ok, msg, rows) {
    bad <- which(!ok | is.na(ok))
    if (length(bad)) problems <<- c(problems, paste0(msg, ": ", paste(rows[bad], collapse = "; ")))
  }

  if (need(scenarios, c("scenario", "lef_min", "lef_mode", "lef_max", "loss_p05", "loss_p95"),
           "scenarios.csv")) {
    s <- scenarios
    check(!duplicated(s$scenario), "scenarios.csv: duplicate scenario name", s$scenario)
    check(s$lef_min >= 0, "scenarios.csv: lef_min must be >= 0", s$scenario)
    check(s$lef_min <= s$lef_mode & s$lef_mode <= s$lef_max & s$lef_min < s$lef_max,
          "scenarios.csv: need lef_min <= lef_mode <= lef_max, with min < max", s$scenario)
    check(s$loss_p05 > 0 & s$loss_p05 < s$loss_p95,
          "scenarios.csv: need 0 < loss_p05 < loss_p95", s$scenario)
  }

  if (!is.null(controls) &&
      need(controls, c("control", "scenario", "freq_red_min", "freq_red_mode", "freq_red_max",
                       "sev_red_min", "sev_red_mode", "sev_red_max", "annual_cost"),
           "controls.csv")) {
    k <- controls
    check(k$scenario %in% scenarios$scenario,
          "controls.csv: scenario not found in scenarios.csv", paste0(k$control, " -> ", k$scenario))
    for (p in c("freq_red", "sev_red")) {
      lo <- k[[paste0(p, "_min")]]
      md <- k[[paste0(p, "_mode")]]
      hi <- k[[paste0(p, "_max")]]
      check(lo >= 0 & hi <= 1, paste0("controls.csv: ", p, "_* must be between 0 and 1"), k$control)
      check(lo <= md & md <= hi & lo < hi,
            paste0("controls.csv: need ", p, "_min <= ", p, "_mode <= ", p, "_max, with min < max"),
            k$control)
    }
    check(k$annual_cost > 0, "controls.csv: annual_cost must be > 0", k$control)
  }

  if (length(problems)) {
    stop("Invalid assumptions in data/assumptions/:\n  - ",
         paste(problems, collapse = "\n  - "), call. = FALSE)
  }
  invisible(TRUE)
}
