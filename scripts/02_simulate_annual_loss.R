# FAIR-style annual loss simulation.
# For each scenario and simulated year:
#   loss event frequency  lambda ~ Triangular(min, mode, max)   (expert estimate)
#   number of events      N      ~ Poisson(lambda)
#   loss per event        L_i    ~ Lognormal from the calibrated 90% interval
# Annual loss = sum of L_i. Events are kept individually so script 03 can apply
# controls to the same simulated history (common random numbers).

library(ggplot2)

N_YEARS <- 20000
set.seed(1234)

scenarios <- read.csv("data/assumptions/scenarios.csv")

events <- do.call(rbind, lapply(seq_len(nrow(scenarios)), function(i) {
  s <- scenarios[i, ]
  lambda <- rtriangle(N_YEARS, s$lef_min, s$lef_mode, s$lef_max)
  counts <- rpois(N_YEARS, lambda)
  par <- lognormal_from_ci(s$loss_p05, s$loss_p95)
  data.frame(scenario = s$scenario,
             year = rep(seq_len(N_YEARS), counts),
             loss = rlnorm(sum(counts), par$meanlog, par$sdlog))
}))
saveRDS(events, "outputs/events.rds")

annual_by_scenario <- function(ev) {
  m <- matrix(0, N_YEARS, nrow(scenarios), dimnames = list(NULL, scenarios$scenario))
  agg <- aggregate(loss ~ scenario + year, data = ev, FUN = sum)
  m[cbind(agg$year, match(agg$scenario, scenarios$scenario))] <- agg$loss
  m
}
annual <- annual_by_scenario(events)
total <- rowSums(annual)

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
  annotate("text", x = 1.2e4, y = 0.065, label = "1-in-20 year", hjust = 0, size = 3.2,
           colour = "grey30") +
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

report_add("## 2. Annual loss distribution\n\n",
           paste(md_table(fmt_tbl), collapse = "\n"), "\n\n",
           "Probability that total annual loss exceeds a threshold:\n\n",
           paste(md_table(exceed), collapse = "\n"), "\n\n",
           "The mean (annualized loss expectancy) sits far above the median: in most years ",
           "losses are modest, and rare ransomware or data-breach years drive the tail.\n\n",
           "![Loss exceedance curve](figures/loss_exceedance_curve.png)\n")
