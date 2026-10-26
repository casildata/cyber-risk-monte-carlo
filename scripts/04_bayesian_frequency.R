# Bayesian update of an incident rate with Metropolis-Hastings.
# Story: 8 insider-misuse incidents were found in 10 years of logs. With a
# near-flat Gamma(1, 0.01) prior on the yearly rate lambda, the posterior is
#   p(lambda | data) ∝ lambda^8 * exp(-10.01 * lambda)  =  Gamma(shape 9, rate 10.01)
# That closed form lets us check the sampler against the exact answer.
#
# Two bugs from the original 2022 version are fixed here:
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
target <- function(lambda) lambda^8 * exp(-RATE * lambda)  # as in the original version
# The samplers are in R/mcmc.R.

N_ITER <- 20000
BURN   <- 1000
fixed <- mh_log_walk(N_ITER, init = 5, step = 0.6, log_target)
post  <- fixed$draws[-seq_len(BURN)]
orig  <- mh_truncated(N_ITER, init = 5, cand_sd = 1.4, target)$draws

exact_q <- qgamma(c(0.025, 0.5, 0.975), SHAPE, RATE)
compare <- data.frame(
  method = c("Exact Gamma(9, 10.01)", "Corrected MH (log random walk)", "Original 2022 MH"),
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
    function() mh_log_walk(N_ITER, 5, 0.6, log_target),
  "Bug 1 only: log random walk, accepted proposals only" =
    function() mh_log_walk(N_ITER, 5, 0.6, log_target, accepted_only = TRUE),
  "Bug 2 only: truncated proposal, no Hastings correction, every iteration" =
    function() mh_truncated(N_ITER, 5, 1.4, target, accepted_only = FALSE),
  "Truncated proposal with Hastings correction, every iteration" =
    function() mh_truncated(N_ITER, 5, 1.4, target, accepted_only = FALSE, hastings = TRUE),
  "Both bugs (original 2022 sampler)" =
    function() mh_truncated(N_ITER, 5, 1.4, target)
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

# ---- Convergence ------------------------------------------------------------------------
# Three more chains of the corrected sampler from spread-out starting points, next to
# the headline chain (started at 5), all after burn-in.
INITS <- c(0.05, 0.5, 2)
chains <- cbind(post, sapply(INITS, function(x0) {
  mh_log_walk(N_ITER, x0, 0.6, log_target)$draws[-seq_len(BURN)]
}))
rhat <- split_rhat(chains)
mcse <- mcse_mean(post)
cat(sprintf("split R-hat %.4f, MCSE of the posterior mean %.4f\n", rhat, mcse))

# ---- Feed the posterior into the simulation ---------------------------------------------
# Replace the expert estimate of the insider-misuse rate with draws from the posterior
# and re-simulate with script 02's seed. Scenarios listed before it in scenarios.csv
# draw the same numbers, so the change comes from the insider-misuse rate.
STORY <- "Insider misuse"
scenarios <- read.csv("data/assumptions/scenarios.csv")
events <- readRDS("outputs/events.rds")
feed <- NULL
if (STORY %in% scenarios$scenario) {
  set.seed(1234)
  ev_post <- simulate_events(scenarios, attr(events, "n_years"),
                             lambda_draws = setNames(list(post), STORY))
  feed_row <- function(label, rate, ev) {
    ann <- annual_losses(ev, scenarios)
    tot <- rowSums(ann)
    data.frame(frequency = label, mean_rate = rate, story_ale = mean(ann[, STORY]),
               story_p95 = unname(quantile(ann[, STORY], 0.95)), total_ale = mean(tot),
               total_p95 = unname(quantile(tot, 0.95)), total_p99 = unname(quantile(tot, 0.99)))
  }
  s <- scenarios[scenarios$scenario == STORY, ]
  feed <- rbind(
    feed_row(sprintf("Expert estimate: triangular(%s, %s, %s)", s$lef_min, s$lef_mode, s$lef_max),
             lef_mean(s), events),
    feed_row("MCMC posterior: 8 incidents in 10 years", mean(post), ev_post)
  )
  write.csv(feed, "outputs/posterior_frequency.csv", row.names = FALSE)
  print(feed)
}

report_add("## 4. Bayesian incident rate (Metropolis-Hastings)\n\n",
           "8 insider-misuse incidents in 10 years with a near-flat prior gives an exact Gamma(9, 10.01) ",
           "posterior, which makes a good test for the sampler.\n\n",
           paste(md_table(compare), collapse = "\n"), "\n\n",
           sprintf("Corrected sampler: acceptance rate %.0f%%, effective sample size ≈ %s of %s ",
                   100 * fixed$acceptance,
                   format(round(effective_sample_size(post)), big.mark = ","),
                   format(length(post), big.mark = ",")),
           "post-burn-in draws. The original version keeps only accepted proposals and uses an ",
           "uncorrected asymmetric proposal; compare its row with the exact answer.\n\n",
           sprintf(paste0("**Convergence.** Split R-hat over four chains (started at %s and 5) ",
                          "is %.3f, and the Monte Carlo standard error of the posterior mean ",
                          "is %.4f. The gap to the exact mean, %+.4f, is %s.\n\n"),
                   paste(INITS, collapse = ", "), rhat, mcse, mean(post) - SHAPE / RATE,
                   if (abs(mean(post) - SHAPE / RATE) < 2 * mcse) "within two standard errors"
                   else "more than two standard errors"),
           "![MCMC](figures/mcmc_posterior.png)\n\n",
           sprintf("**Which bug does what.** Each variant run as %d chains of %s iterations, ",
                   N_CHAINS, format(N_ITER, big.mark = ",")),
           sprintf("first %s dropped; exact posterior mean %.3f.\n\n",
                   format(BURN, big.mark = ","), SHAPE / RATE),
           paste(md_table(bugs), collapse = "\n"), "\n",
           if (!is.null(feed))
             paste0("\n**Feeding the posterior into the simulation.** Script 02 draws the ",
                    tolower(STORY), " rate from the analyst's min / mode / max. Here the rate is drawn ",
                    "from the posterior instead and the years are simulated again with the ",
                    "same seed. The data say incidents are ",
                    sprintf("%.1f", feed$mean_rate[2] / feed$mean_rate[1]),
                    " times as frequent as the analyst thought. The headline results keep the ",
                    "expert estimate, because the 8 incidents are part of an illustrative ",
                    "story; with real incident logs, this is the step that replaces a guess ",
                    "with evidence.\n\n",
                    paste(md_table(setNames(data.frame(
                      feed$frequency, sprintf("%.3f", feed$mean_rate),
                      dollars_sig(feed$story_ale), dollars_sig(feed$story_p95),
                      dollars_sig(feed$total_ale), dollars_sig(feed$total_p95),
                      dollars_sig(feed$total_p99)),
                      c("Frequency", "Mean events / yr", paste(STORY, "ALE"),
                        paste(STORY, "P95"), "Total ALE", "Total P95", "Total P99"))),
                      collapse = "\n"), "\n"))
