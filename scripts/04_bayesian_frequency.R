# Bayesian update of an incident rate with Metropolis-Hastings.
# Story: 8 account-takeover incidents were found in 10 years of logs. With a
# near-flat Gamma(1, 0.01) prior on the yearly rate lambda, the posterior is
#   p(lambda | data) ∝ lambda^8 * exp(-10.01 * lambda)  =  Gamma(shape 9, rate 10.01)
# That closed form lets us check the sampler against the exact answer.
#
# Two bugs from the original coursework version are fixed here:
#   1. Only accepted proposals were stored. MH must record the current state on
#      EVERY iteration (a rejection repeats the old value), or the chain is biased.
#   2. Proposals came from a normal truncated at 0. Its normalizing constant
#      depends on the current state, so the proposal is not symmetric and the
#      plain ratio g(cand)/g(now) needs a Hastings correction it never had. We now
#      random-walk on log(lambda), where the proposal is symmetric, and include
#      the Jacobian.
# A bug-isolation table at the end runs each bug on its own over several chains.

library(ggplot2)

set.seed(321)
SHAPE <- 9
RATE  <- 10.01
log_target <- function(lambda) (SHAPE - 1) * log(lambda) - RATE * lambda

# accepted_only = TRUE reproduces bug 1. Each sampler returns the stored draws and
# the iteration each was stored at, so burn-in is dropped the same way for all.
mh_log_walk <- function(n_iter, init, step, accepted_only = FALSE) {
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

# The coursework sampler: a normal proposal truncated below at 0. The defaults
# reproduce the original (both bugs); hastings = TRUE adds the missing correction
# q(now | cand) / q(cand | now) = P(N(now, sd) > 0) / P(N(cand, sd) > 0).
mh_truncated <- function(n_iter, init, cand_sd, accepted_only = TRUE, hastings = FALSE) {
  rtrunc0 <- function(mean, sd) {  # normal truncated below at 0 (inverse CDF)
    lo <- pnorm(0, mean, sd)
    qnorm(runif(1, lo, 1), mean, sd)
  }
  g <- function(x) x^8 * exp(-RATE * x)
  x_now <- init
  draws <- iter <- numeric(n_iter)
  n_kept <- 0
  for (i in seq_len(n_iter)) {
    x_cand <- rtrunc0(x_now, cand_sd)
    ratio <- g(x_cand) / g(x_now)
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

N_ITER <- 20000
BURN   <- 1000
fixed <- mh_log_walk(N_ITER, init = 5, step = 0.6)
post  <- fixed$draws[-seq_len(BURN)]
orig  <- mh_truncated(N_ITER, init = 5, cand_sd = 1.4)$draws

exact_q <- qgamma(c(0.025, 0.5, 0.975), SHAPE, RATE)
compare <- data.frame(
  method = c("Exact Gamma(9, 10.01)", "Corrected MH (log random walk)", "Original coursework MH"),
  mean = round(c(SHAPE / RATE, mean(post), mean(orig)), 3),
  q025 = round(c(exact_q[1], quantile(post, 0.025), quantile(orig, 0.025)), 3),
  median = round(c(exact_q[2], median(post), median(orig)), 3),
  q975 = round(c(exact_q[3], quantile(post, 0.975), quantile(orig, 0.975)), 3),
  draws_kept = c(NA, length(post), length(orig))
)
print(compare)
cat(sprintf("acceptance rate %.2f, effective sample size %.0f\n",
            fixed$acceptance, effective_sample_size(post)))

trace <- data.frame(iter = seq_along(fixed$draws), lambda = fixed$draws)
p1 <- ggplot(trace[seq(1, nrow(trace), 5), ], aes(iter, lambda)) +
  geom_line(colour = "#2b6cb0", linewidth = 0.3) +
  geom_vline(xintercept = BURN, linetype = 2, colour = "grey40") +
  labs(title = "Trace (every 5th draw)", x = "Iteration", y = expression(lambda)) +
  theme_minimal(base_size = 11)
dens <- data.frame(lambda = seq(0.01, 2.5, length.out = 300))
dens$exact <- dgamma(dens$lambda, SHAPE, RATE)
p2 <- ggplot(data.frame(lambda = post), aes(lambda)) +
  geom_histogram(aes(y = after_stat(density)), bins = 60, fill = "#90cdf4", colour = "white") +
  geom_line(data = dens, aes(lambda, exact), colour = "#e53e3e", linewidth = 1) +
  labs(title = "Posterior vs. exact Gamma(9, 10.01)", x = "Incidents per year (lambda)",
       y = "Density") +
  theme_minimal(base_size = 11)
save_plot(patchwork::wrap_plots(p1, p2, ncol = 2), "mcmc_posterior.png", 10, 4)

# ---- Bug isolation ------------------------------------------------------------------
# One chain can't separate a bias of a few hundredths from noise, so run each variant
# as N_CHAINS independent chains, drop the first BURN iterations of each, and report
# the mean and chain-to-chain spread of the posterior mean.
N_CHAINS <- 10
variants <- list(
  "Corrected: log random walk, every iteration" =
    function() mh_log_walk(N_ITER, 5, 0.6),
  "Bug 1 only: log random walk, accepted proposals only" =
    function() mh_log_walk(N_ITER, 5, 0.6, accepted_only = TRUE),
  "Bug 2 only: truncated proposal, no Hastings correction, every iteration" =
    function() mh_truncated(N_ITER, 5, 1.4, accepted_only = FALSE),
  "Truncated proposal with Hastings correction, every iteration" =
    function() mh_truncated(N_ITER, 5, 1.4, accepted_only = FALSE, hastings = TRUE),
  "Both bugs (original coursework sampler)" =
    function() mh_truncated(N_ITER, 5, 1.4)
)
chain_means <- sapply(variants, function(run) {
  replicate(N_CHAINS, {
    ch <- run()
    mean(ch$draws[ch$iter > BURN])
  })
})
bugs <- data.frame(
  Sampler = names(variants),
  `Posterior mean` = sprintf("%.3f", colMeans(chain_means)),
  `Chain-to-chain sd` = sprintf("%.3f", apply(chain_means, 2, sd)),
  `Bias vs. exact` = sprintf("%+.3f", colMeans(chain_means) - SHAPE / RATE),
  check.names = FALSE, row.names = NULL
)
write.csv(bugs, "outputs/mcmc_bug_isolation.csv", row.names = FALSE)
print(bugs)

report_add("## 4. Bayesian incident rate (Metropolis-Hastings)\n\n",
           "8 incidents in 10 years with a near-flat prior gives an exact Gamma(9, 10.01) ",
           "posterior, which makes a good test for the sampler.\n\n",
           paste(md_table(compare), collapse = "\n"), "\n\n",
           sprintf("Corrected sampler: acceptance rate %.0f%%, effective sample size ≈ %s of %s ",
                   100 * fixed$acceptance,
                   format(round(effective_sample_size(post)), big.mark = ","),
                   format(length(post), big.mark = ",")),
           "post-burn-in draws. The original version keeps only accepted proposals and uses an ",
           "uncorrected asymmetric proposal; compare its row with the exact answer.\n\n",
           "![MCMC](figures/mcmc_posterior.png)\n\n",
           sprintf("**Which bug does what.** Each variant run as %d chains of %s iterations, ",
                   N_CHAINS, format(N_ITER, big.mark = ",")),
           sprintf("first %s dropped; exact posterior mean %.3f.\n\n",
                   format(BURN, big.mark = ","), SHAPE / RATE),
           paste(md_table(bugs), collapse = "\n"), "\n")
