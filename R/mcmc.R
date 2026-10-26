# Metropolis-Hastings samplers for a positive parameter (an incident rate), used
# by scripts/04_bayesian_frequency.R and checked in tests/testthat/.

# Random walk on log(lambda). `log_target` is the unnormalized log density of lambda.
# accepted_only = TRUE reproduces bug 1. Each sampler returns the stored draws and
# the iteration each was stored at, so burn-in is dropped the same way for all.
mh_log_walk <- function(n_iter, init, step, log_target, accepted_only = FALSE) {
  theta <- log(init)
  # log density of theta = log(lambda) includes the Jacobian d lambda / d theta = lambda
  log_p <- function(t) log_target(exp(t)) + t
  lp_now <- log_p(theta)
  draws <- iter <- numeric(n_iter)
  n_kept <- 0
  accepted <- 0
  for (i in seq_len(n_iter)) {
    cand <- theta + rnorm(1, 0, step)
    lp_cand <- log_p(cand)
    moved <- log(runif(1)) < lp_cand - lp_now
    if (moved) {
      theta <- cand
      lp_now <- lp_cand
      accepted <- accepted + 1
    }
    if (moved || !accepted_only) {  # correct MH records every iteration
      n_kept <- n_kept + 1
      draws[n_kept] <- exp(theta)
      iter[n_kept] <- i
    }
  }
  list(draws = draws[seq_len(n_kept)], iter = iter[seq_len(n_kept)],
       acceptance = accepted / n_iter)
}

# The original 2022 sampler: a normal proposal truncated below at 0. The defaults
# reproduce the original (both bugs); hastings = TRUE adds the missing correction
# q(now | cand) / q(cand | now) = P(N(now, sd) > 0) / P(N(cand, sd) > 0).
mh_truncated <- function(n_iter, init, cand_sd, target, accepted_only = TRUE,
                         hastings = FALSE) {
  rtrunc0 <- function(mean, sd) {  # normal truncated below at 0 (inverse CDF)
    lo <- pnorm(0, mean, sd)
    qnorm(runif(1, lo, 1), mean, sd)
  }
  x_now <- init
  draws <- iter <- numeric(n_iter)
  n_kept <- 0
  for (i in seq_len(n_iter)) {
    x_cand <- rtrunc0(x_now, cand_sd)
    ratio <- target(x_cand) / target(x_now)
    if (hastings) ratio <- ratio * pnorm(x_now / cand_sd) / pnorm(x_cand / cand_sd)
    moved <- runif(1) < ratio
    if (moved) x_now <- x_cand
    if (moved || !accepted_only) {
      n_kept <- n_kept + 1
      draws[n_kept] <- x_now
      iter[n_kept] <- i
    }
  }
  list(draws = draws[seq_len(n_kept)], iter = iter[seq_len(n_kept)])
}

effective_sample_size <- function(x, max_lag = 200) {
  rho <- acf(x, lag.max = max_lag, plot = FALSE)$acf[-1]
  cut <- which(rho < 0.05)[1]
  if (is.na(cut)) cut <- length(rho)
  length(x) / (1 + 2 * sum(rho[seq_len(cut - 1)]))
}

# Split R-hat (Gelman et al.): each chain (a column of `chains`) is cut in half and
# the between-half variance compared with the within-half variance. Close to 1
# (below about 1.01) when the chains agree.
split_rhat <- function(chains) {
  n <- nrow(chains) %/% 2
  halves <- cbind(chains[seq_len(n), , drop = FALSE], chains[n + seq_len(n), , drop = FALSE])
  w <- mean(apply(halves, 2, var))
  b <- n * var(colMeans(halves))
  sqrt(((n - 1) / n * w + b / n) / w)
}

# Monte Carlo standard error of a posterior mean: sd / sqrt(effective sample size).
mcse_mean <- function(x) sd(x) / sqrt(effective_sample_size(x))
