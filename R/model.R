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

# Per-scenario widening of the loss interval in the two-level analysis: the optional
# `loss_uncertainty` column, else `default` (1 = loss sizes treated as known).
loss_uncertainty_of <- function(s, default = 1) {
  f <- if ("loss_uncertainty" %in% names(s)) s$loss_uncertainty else NA
  if (is.na(f)) default else f
}

# n single losses for one scenario: lognormal from the 90% interval, capped.
draw_losses <- function(n, s, loss_cap = NA) {
  par <- lognormal_from_ci(s$loss_p05, s$loss_p95)
  pmin(rlnorm(n, par$meanlog, par$sdlog), loss_cap_of(s, loss_cap), na.rm = TRUE)
}

# For each scenario and simulated year:
#   lambda ~ frequency distribution, N ~ Poisson(lambda), L_i ~ Lognormal (capped).
# Returns one row per loss event. Years without events have no rows, so the
# number of simulated years is stored as an attribute.
# `lambda_draws` (scenario name -> draws of the event rate, e.g. an MCMC posterior)
# replaces the min / mode / max estimate for those scenarios.
# Double extortion: a share `p_ext` of events in scenario ext[1] also cause an
# ext[2] loss. The standalone ext[2] rate is lowered by the expected number of
# those events, so its frequency is unchanged on average and only the dependence
# between the two scenarios changes. p_ext = 0 draws nothing extra.
simulate_events <- function(scenarios, n_years, lef_dist = "triangular", loss_cap = NA,
                            lambda_draws = list(), p_ext = 0,
                            ext = c("Ransomware", "Customer data breach")) {
  if (p_ext > 0) {
    from <- match(ext[1], scenarios$scenario)
    to <- match(ext[2], scenarios$scenario)
    if (anyNA(c(from, to))) stop("double extortion needs scenarios ", ext[1], " and ", ext[2],
                                 call. = FALSE)
    shift <- p_ext * lef_mean(scenarios[from, ], lef_dist_of(scenarios[from, ], lef_dist))
    if (scenarios$lef_min[to] < shift) {
      stop("p_ext too large: ", ext[2], " lef_min would fall below 0", call. = FALSE)
    }
    for (col in c("lef_min", "lef_mode", "lef_max")) {
      scenarios[[col]][to] <- scenarios[[col]][to] - shift
    }
  }
  events <- do.call(rbind, lapply(seq_len(nrow(scenarios)), function(i) {
    s <- scenarios[i, ]
    lambda <- if (s$scenario %in% names(lambda_draws)) {
      d <- lambda_draws[[s$scenario]]
      d[sample.int(length(d), n_years, replace = TRUE)]  # sample(d) misreads a single draw
    } else {
      draw_lef(n_years, s, lef_dist_of(s, lef_dist))
    }
    counts <- rpois(n_years, lambda)
    data.frame(scenario = rep(s$scenario, sum(counts)),
               year = rep(seq_len(n_years), counts),
               loss = draw_losses(sum(counts), s, loss_cap))
  }))
  if (p_ext > 0) {
    from_years <- events$year[events$scenario == ext[1]]
    leak <- from_years[runif(length(from_years)) < p_ext]
    events <- rbind(events, data.frame(scenario = rep(ext[2], length(leak)), year = leak,
                                       loss = draw_losses(length(leak), scenarios[to, ], loss_cap)))
  }
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

# Total of v per simulated year, with 0 for years that have no rows.
sum_by_year <- function(year, v, n_years) {
  out <- as.numeric(tapply(v, factor(year, levels = seq_len(n_years)), sum))
  out[is.na(out)] <- 0
  out
}

# Apply a control to one scenario's events (common random numbers): each event is
# prevented with probability r_f, and surviving events cost (1 - r_s) as much.
# r_f and r_s are one value per simulated year, or a single value for all years.
# Returns the loss per year before and after, and the loss avoided. The per-event
# loss multiplier (0 if prevented, else 1 - r_s) is kept as attribute "factor".
apply_control <- function(ev, r_f, r_s, n_years) {
  r_f <- rep_len(r_f, n_years)
  r_s <- rep_len(r_s, n_years)
  prevented <- runif(nrow(ev)) < r_f[ev$year]
  f <- ifelse(prevented, 0, 1 - r_s[ev$year])
  before <- sum_by_year(ev$year, ev$loss, n_years)
  after <- sum_by_year(ev$year, ev$loss * f, n_years)
  out <- data.frame(before = before, after = after, avoided = before - after)
  attr(out, "factor") <- f
  out
}

# Loss avoided per year by several controls together. rows[[j]] are the rows of
# `events` that control j acts on and factors[[j]] its per-event multipliers.
# Controls on the same scenario compound: a second control acts on what the first
# leaves, L * f1 * f2, so the avoided losses are not simply added.
combined_avoided <- function(events, rows, factors, n_years) {
  keep <- rep(1, nrow(events))
  for (j in seq_along(rows)) keep[rows[[j]]] <- keep[rows[[j]]] * factors[[j]]
  sum_by_year(events$year, events$loss * (1 - keep), n_years)
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

# Two-level view of a control: what we don't know (the long-run event rate, how
# well the control works and, optionally, the size of a typical loss) is drawn once
# per outer draw and held fixed, instead of being redrawn every simulated year.
# Given those, the expected loss avoided per year has a closed form, so no inner
# simulation is needed:
#   avoided = lambda * m * E[L] * (1 - (1 - r_f) * (1 - r_s))
# m scales the expected loss per event. With loss_uncertainty f > 1 (column in
# scenarios.csv), m is lognormal with about 90% of draws between 1/f and f, centered
# so E[m] = 1. With f = 1 (the default), loss sizes are treated as known and no
# extra draws are made.
control_uncertainty <- function(ctl, s, n_draws = 10000, lef_dist = "triangular",
                                loss_cap = NA) {
  lambda <- draw_lef(n_draws, s, lef_dist_of(s, lef_dist))
  r_f <- rtriangle(n_draws, ctl$freq_red_min, ctl$freq_red_mode, ctl$freq_red_max)
  r_s <- rtriangle(n_draws, ctl$sev_red_min, ctl$sev_red_mode, ctl$sev_red_max)
  f <- loss_uncertainty_of(s)
  m <- 1
  if (f > 1) {
    sdlog <- log(f) / qnorm(0.95)
    m <- rlnorm(n_draws, -sdlog^2 / 2, sdlog)
  }
  avoided <- lambda * m * expected_event_loss(s, loss_cap) * (1 - (1 - r_f) * (1 - r_s))
  data.frame(lambda = lambda, r_f = r_f, r_s = r_s, m = m, avoided = avoided,
             rosi = (avoided - ctl$annual_cost) / ctl$annual_cost)
}

# Expected value of perfect information for a buy / don't-buy decision: the most
# it is worth paying to learn the true inputs before deciding. With the draws'
# net benefit (loss avoided - cost), it is the expected net benefit if we could
# choose per draw, minus that of the best choice made now.
evpi <- function(net) mean(pmax(net, 0)) - max(mean(net), 0)

# P(X > x) for each x in `grid`.
exceedance <- function(v, grid) {
  v <- sort(v)
  1 - findInterval(grid, v) / length(v)
}
