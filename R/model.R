# The simulation model, separated from the scripts so it can be tested.
# Scripts 02 and 03 call these functions; tests/testthat/ checks them.

# Draw the loss event frequency (events per year) for one scenario. `dist` is
# "triangular" (the default) or "pert".
draw_lef <- function(n, s, dist = "triangular") {
  switch(dist,
         triangular = rtriangle(n, s$lef_min, s$lef_mode, s$lef_max),
         pert = rpert(n, s$lef_min, s$lef_mode, s$lef_max),
         stop("unknown frequency distribution: ", dist, call. = FALSE))
}

# Expected loss event frequency under the triangular or PERT estimate.
lef_mean <- function(s, dist = lef_dist_of(s)) {
  switch(dist,
         triangular = (s$lef_min + s$lef_mode + s$lef_max) / 3,
         pert = (s$lef_min + 4 * s$lef_mode + s$lef_max) / 6,
         stop("unknown frequency distribution: ", dist, call. = FALSE))
}

# Per-scenario frequency distribution: the optional `lef_dist` column, else `default`.
lef_dist_of <- function(s, default = "triangular") {
  d <- if ("lef_dist" %in% names(s)) s$lef_dist else NA
  if (is.na(d) || !nzchar(d)) default else d
}

# Per-scenario cap on a single loss: the optional `loss_cap` column, else `default`
# (NA = uncapped).
loss_cap_of <- function(s, default = NA) {
  cap <- if ("loss_cap" %in% names(s)) s$loss_cap else NA
  if (is.na(cap)) default else cap
}

# For each scenario and simulated year:
#   lambda ~ frequency distribution, N ~ Poisson(lambda), L_i ~ Lognormal (capped).
# Returns one row per loss event. Years without events have no rows, so the
# number of simulated years is stored as an attribute.
simulate_events <- function(scenarios, n_years, lef_dist = "triangular", loss_cap = NA) {
  events <- do.call(rbind, lapply(seq_len(nrow(scenarios)), function(i) {
    s <- scenarios[i, ]
    lambda <- draw_lef(n_years, s, lef_dist_of(s, lef_dist))
    counts <- rpois(n_years, lambda)
    par <- lognormal_from_ci(s$loss_p05, s$loss_p95)
    data.frame(scenario = s$scenario,
               year = rep(seq_len(n_years), counts),
               loss = pmin(rlnorm(sum(counts), par$meanlog, par$sdlog),
                           loss_cap_of(s, loss_cap), na.rm = TRUE))
  }))
  attr(events, "n_years") <- n_years
  events
}

# Years x scenarios matrix of total annual loss (zeros included).
annual_losses <- function(events, scenarios) {
  n_years <- attr(events, "n_years")
  m <- matrix(0, n_years, nrow(scenarios), dimnames = list(NULL, scenarios$scenario))
  if (nrow(events) == 0) return(m)
  agg <- aggregate(loss ~ scenario + year, data = events, FUN = sum)
  m[cbind(agg$year, match(agg$scenario, scenarios$scenario))] <- agg$loss
  m
}

# Apply a control to one scenario's events (common random numbers): each event is
# prevented with probability r_f, and surviving events cost (1 - r_s) as much.
# r_f and r_s are one value per simulated year, or a single value for all years.
# Returns the loss per year before and after, and the loss avoided.
apply_control <- function(ev, r_f, r_s, n_years) {
  r_f <- rep_len(r_f, n_years)
  r_s <- rep_len(r_s, n_years)
  prevented <- runif(nrow(ev)) < r_f[ev$year]
  loss_after <- ifelse(prevented, 0, ev$loss * (1 - r_s[ev$year]))

  per_year <- function(v) {
    out <- as.numeric(tapply(v, factor(ev$year, levels = seq_len(n_years)), sum))
    out[is.na(out)] <- 0
    out
  }
  before <- per_year(ev$loss)
  after <- per_year(loss_after)
  data.frame(before = before, after = after, avoided = before - after)
}

# Mean loss of one event: the lognormal mean, or the mean of the capped lognormal.
expected_event_loss <- function(s, loss_cap = NA) {
  par <- lognormal_from_ci(s$loss_p05, s$loss_p95)
  cap <- loss_cap_of(s, loss_cap)
  if (is.na(cap)) return(exp(par$meanlog + par$sdlog^2 / 2))
  # E[min(L, c)] = E[L; L < c] + c * P(L >= c)
  z <- (log(cap) - par$meanlog) / par$sdlog
  exp(par$meanlog + par$sdlog^2 / 2) * pnorm(z - par$sdlog) + cap * (1 - pnorm(z))
}

# Two-level view of a control: what we don't know (the long-run event rate and how
# well the control works) is drawn once per outer draw and held fixed, instead of
# being redrawn every simulated year. Given those, the expected loss avoided per
# year has a closed form, so no inner simulation is needed:
#   avoided = lambda * E[L] * (1 - (1 - r_f) * (1 - r_s))
# Severity parameters are treated as known, so the band is, if anything, too narrow.
control_uncertainty <- function(ctl, s, n_draws = 10000, lef_dist = "triangular",
                                loss_cap = NA) {
  lambda <- draw_lef(n_draws, s, lef_dist_of(s, lef_dist))
  r_f <- rtriangle(n_draws, ctl$freq_red_min, ctl$freq_red_mode, ctl$freq_red_max)
  r_s <- rtriangle(n_draws, ctl$sev_red_min, ctl$sev_red_mode, ctl$sev_red_max)
  avoided <- lambda * expected_event_loss(s, loss_cap) * (1 - (1 - r_f) * (1 - r_s))
  data.frame(lambda = lambda, r_f = r_f, r_s = r_s, avoided = avoided,
             rosi = (avoided - ctl$annual_cost) / ctl$annual_cost)
}

# P(X > x) for each x in `grid`.
exceedance <- function(v, grid) {
  v <- sort(v)
  1 - findInterval(grid, v) / length(v)
}
