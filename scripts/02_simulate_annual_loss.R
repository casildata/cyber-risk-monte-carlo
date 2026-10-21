# FAIR-style annual loss simulation.
# For each scenario and simulated year:
#   loss event frequency  lambda ~ Triangular(min, mode, max)   (expert estimate)
#   number of events      N      ~ Poisson(lambda)
#   loss per event        L_i    ~ Lognormal from the calibrated 90% interval
# Annual loss = sum of L_i. Events are kept individually so script 03 can apply
# controls to the same simulated history (common random numbers).
# The model itself is in R/model.R.

library(ggplot2)

N_YEARS <- 20000
set.seed(1234)

scenarios <- read.csv("data/assumptions/scenarios.csv")
validate_inputs(scenarios)

# Years with no events have no rows, so simulate_events() stores the number of
# simulated years with the events for script 03
events <- simulate_events(scenarios, N_YEARS)
saveRDS(events, "outputs/events.rds")

annual <- annual_losses(events, scenarios)
total <- rowSums(annual)

# Year-by-scenario losses for downstream use (e.g. tail-risk optimization of a
# control budget): one row per simulated year, whole dollars
write.csv(data.frame(year = seq_len(N_YEARS), round(annual), Total = round(total),
                     check.names = FALSE),
          gzfile("outputs/annual_loss_by_year.csv.gz"), row.names = FALSE)

summarise_losses <- function(v) {
  c(mean = mean(v), median = median(v), p90 = unname(quantile(v, 0.90)),
    p95 = unname(quantile(v, 0.95)), p99 = unname(quantile(v, 0.99)),
    p_any_loss = mean(v > 0))
}
summary_tbl <- as.data.frame(t(sapply(c(as.data.frame(annual), list(Total = total)),
                                      summarise_losses)))
summary_tbl <- cbind(scenario = rownames(summary_tbl), summary_tbl, row.names = NULL)
write.csv(summary_tbl, "outputs/annual_loss_summary.csv", row.names = FALSE)
print(summary_tbl)

thresholds <- c(1e6, 5e6, 10e6)
exceed <- data.frame(threshold = dollars(thresholds),
                     probability = sprintf("%.1f%%", 100 * sapply(thresholds, function(t) mean(total > t))))

# ---- Loss exceedance curve ------------------------------------------------------
grid <- 10^seq(4, 8, length.out = 200)
lec <- do.call(rbind, lapply(c(colnames(annual), "Total"), function(nm) {
  v <- if (nm == "Total") total else annual[, nm]
  data.frame(scenario = nm, loss = grid, p_exceed = sapply(grid, function(g) mean(v > g)))
}))
lec$scenario <- factor(lec$scenario, levels = c("Total", colnames(annual)))
p <- ggplot(subset(lec, p_exceed > 0), aes(loss, p_exceed, colour = scenario,
                                           linewidth = scenario == "Total")) +
  geom_line() +
  scale_linewidth_manual(values = c(0.6, 1.4), guide = "none") +
  scale_colour_manual(values = c("black", "#2b6cb0", "#dd6b20", "#38a169", "#805ad5", "#e53e3e")) +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  scale_y_continuous(labels = scales::label_percent()) +
  geom_hline(yintercept = 0.05, linetype = 3, colour = "grey40") +
  annotate("text", x = 1.2e4, y = 0.05, label = "1-in-20 year", hjust = 0, vjust = -0.6,
           size = 3.2, colour = "grey30") +
  labs(title = "Loss exceedance curve",
       subtitle = sprintf("Probability that annual cyber loss exceeds x (%s simulated years)",
                          format(N_YEARS, big.mark = ",")),
       x = "Annual loss (log scale)", y = "P(annual loss > x)", colour = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "right")
save_plot(p, "loss_exceedance_curve.png", 9, 5)

fmt_tbl <- summary_tbl
for (col in c("mean", "median", "p90", "p95", "p99")) fmt_tbl[[col]] <- dollars(fmt_tbl[[col]])
fmt_tbl$p_any_loss <- sprintf("%.0f%%", 100 * fmt_tbl$p_any_loss)
names(fmt_tbl) <- c("Scenario", "Mean (ALE)", "Median", "P90", "P95 (1-in-20)",
                    "P99 (1-in-100)", "P(any loss)")

# ---- Monte Carlo error ------------------------------------------------------------
# The figures above are exact for seed 1234; another seed would move them. Bootstrap
# the simulated years to estimate by how much. Runs last so it changes nothing above.
MC_B <- 200
set.seed(5678)
mc_se <- function(v) {
  boots <- replicate(MC_B, {
    s <- sample(v, replace = TRUE)
    c(mean(s), quantile(s, c(0.95, 0.99), names = FALSE))
  })
  apply(boots, 1, sd)
}
se_tbl <- as.data.frame(t(sapply(c(as.data.frame(annual), list(Total = total)), mc_se)))
names(se_tbl) <- c("se_mean", "se_p95", "se_p99")
se_tbl <- cbind(scenario = rownames(se_tbl), se_tbl, row.names = NULL)
write.csv(se_tbl, "outputs/annual_loss_mc_error.csv", row.names = FALSE)

pm <- function(est, se) paste0(dollars_sig(est), " ± ", dollars_sig(se, 2))
se_fmt <- data.frame(
  Scenario = summary_tbl$scenario,
  `Mean (ALE)` = pm(summary_tbl$mean, se_tbl$se_mean),
  `P95 (1-in-20)` = pm(summary_tbl$p95, se_tbl$se_p95),
  `P99 (1-in-100)` = pm(summary_tbl$p99, se_tbl$se_p99),
  check.names = FALSE
)

report_add("## 2. Annual loss distribution\n\n",
           paste(md_table(fmt_tbl), collapse = "\n"), "\n\n",
           "Probability that total annual loss exceeds a threshold:\n\n",
           paste(md_table(exceed), collapse = "\n"), "\n\n",
           "The mean (annualized loss expectancy) sits far above the median: in most years ",
           "losses are modest, and rare ransomware or data-breach years drive the tail.\n\n",
           "**Monte Carlo error.** The table above is exact for this seed, not to the dollar. ",
           "Bootstrap standard errors over the ", format(N_YEARS, big.mark = ","),
           " simulated years (", MC_B, " resamples) show how far another seed could move ",
           "each figure. They measure simulation noise only, not uncertainty in the ",
           "assumptions:\n\n",
           paste(md_table(se_fmt), collapse = "\n"), "\n\n",
           "![Loss exceedance curve](figures/loss_exceedance_curve.png)\n")

# ---- Sensitivity: frequency distribution and a loss cap ---------------------------
# Re-run with the same seed, changing one modeling choice at a time:
#   - beta-PERT instead of triangular for the event rate (the usual FAIR choice)
#   - a cap on any single loss. Uncapped, the largest simulated event is far beyond
#     what a mid-size company could pay; $10M is an illustrative ceiling.
SENS_CAP <- 10e6
sens_run <- function(label, lef_dist = "triangular", loss_cap = NA) {
  set.seed(1234)
  ev <- simulate_events(scenarios, N_YEARS, lef_dist = lef_dist, loss_cap = loss_cap)
  tot <- rowSums(annual_losses(ev, scenarios))
  data.frame(Model = label, ale = mean(tot), p95 = unname(quantile(tot, 0.95)),
             p99 = unname(quantile(tot, 0.99)), p_over_5m = mean(tot > 5e6),
             largest_event = max(ev$loss))
}
sens <- rbind(
  sens_run("Base: triangular frequency, uncapped"),
  sens_run("Beta-PERT frequency", lef_dist = "pert"),
  sens_run(paste0("Single loss capped at ", dollars_sig(SENS_CAP, 2)), loss_cap = SENS_CAP),
  sens_run("Beta-PERT and capped", lef_dist = "pert", loss_cap = SENS_CAP)
)
write.csv(sens, "outputs/sensitivity.csv", row.names = FALSE)
sens_fmt <- data.frame(
  Model = sens$Model,
  `Total ALE` = dollars_sig(sens$ale),
  `P95 (1-in-20)` = dollars_sig(sens$p95),
  `P99 (1-in-100)` = dollars_sig(sens$p99),
  `P(> $5M)` = sprintf("%.1f%%", 100 * sens$p_over_5m),
  `Largest single event` = dollars_sig(sens$largest_event),
  check.names = FALSE
)
report_add("### Sensitivity to modeling choices\n\n",
           "Same seed, one choice changed at a time. Beta-PERT uses the same min / mode / max ",
           "as the triangular but puts less weight near the extremes, so it lowers the mean ",
           "event rate whenever the mode sits closer to the minimum, as it does for every ",
           "scenario here. The cap applies to each single loss, so it cannot move a ",
           "percentile of annual loss that is already below the cap.\n\n",
           paste(md_table(sens_fmt), collapse = "\n"), "\n")
