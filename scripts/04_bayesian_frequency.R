# Bayesian update of an incident rate with Metropolis-Hastings.
# Story: 8 account-takeover incidents were found in 10 years of logs. With a
# near-flat Gamma(1, 0.01) prior on the yearly rate lambda, the posterior is
#   p(lambda | data) ∝ lambda^8 * exp(-10.01 * lambda)  =  Gamma(shape 9, rate 10.01)
# That closed form lets us check the sampler against the exact answer.
#
# Two bugs from the original coursework version are fixed here:
#   1. Only accepted proposals were stored. MH must record the current state on
#      EVERY iteration (a rejection repeats the old value), or the chain is biased.
#   2. Proposals came from a normal truncated at 0, which is not symmetric, so the
#      plain ratio g(cand)/g(now) was wrong. We now random-walk on log(lambda),
#      where the proposal is symmetric, and include the Jacobian.

library(ggplot2)

set.seed(321)
SHAPE <- 9
RATE  <- 10.01
log_target <- function(lambda) (SHAPE - 1) * log(lambda) - RATE * lambda

mh_log_walk <- function(n_iter, init, step) {
  theta <- log(init)
  # log density of theta = log(lambda) includes the Jacobian d lambda / d theta = lambda
  log_p <- function(t) log_target(exp(t)) + t
  lp_now <- log_p(theta)
  draws <- numeric(n_iter)
  accepted <- 0
  for (i in seq_len(n_iter)) {
    cand <- theta + rnorm(1, 0, step)
    lp_cand <- log_p(cand)
    if (log(runif(1)) < lp_cand - lp_now) {
      theta <- cand
      lp_now <- lp_cand
      accepted <- accepted + 1
    }
    draws[i] <- exp(theta)  # recorded every iteration
  }
  list(draws = draws, acceptance = accepted / n_iter)
}

# The coursework version, kept to show the effect of the bugs.
mh_original <- function(n_iter, init, cand_sd) {
  rtrunc0 <- function(mean, sd) {  # normal truncated below at 0 (inverse CDF)
    lo <- pnorm(0, mean, sd)
    qnorm(runif(1, lo, 1), mean, sd)
  }
  g <- function(x) x^8 * exp(-RATE * x)
  x_now <- init
  out <- c()
  for (i in seq_len(n_iter)) {
    x_cand <- rtrunc0(x_now, cand_sd)
    if (runif(1) < g(x_cand) / g(x_now)) {
      x_now <- x_cand
      out <- c(out, x_now)  # only accepted values stored
    }
  }
  out
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
orig  <- mh_original(N_ITER, init = 5, cand_sd = 1.4)

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
           "![MCMC](figures/mcmc_posterior.png)\n")
