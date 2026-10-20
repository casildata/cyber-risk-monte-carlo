# Return on security investment (ROSI) for candidate controls.
# Each control is applied to the SAME simulated events from script 02:
#   - frequency reduction r_f: each event is prevented with probability r_f
#     (thinning a Poisson process gives exactly Poisson(lambda * (1 - r_f)))
#   - severity reduction r_s: surviving events cost (1 - r_s) as much
# Both reductions are uncertain (triangular per simulated year).
# ROSI = (ALE before - ALE after - annual cost) / annual cost.

library(ggplot2)

set.seed(99)
events   <- readRDS("outputs/events.rds")
controls <- read.csv("data/assumptions/controls.csv")
validate_inputs(read.csv("data/assumptions/scenarios.csv"), controls)
n_years  <- attr(events, "n_years")

bootstrap_mean_ci <- function(v, B = 2000) {
  means <- replicate(B, mean(sample(v, replace = TRUE)))
  unname(quantile(means, c(0.025, 0.975)))
}

results <- lapply(seq_len(nrow(controls)), function(i) {
  ctl <- controls[i, ]
  ev  <- events[events$scenario == ctl$scenario, ]
  r_f <- rtriangle(n_years, ctl$freq_red_min, ctl$freq_red_mode, ctl$freq_red_max)
  r_s <- rtriangle(n_years, ctl$sev_red_min, ctl$sev_red_mode, ctl$sev_red_max)

  prevented <- runif(nrow(ev)) < r_f[ev$year]
  loss_after <- ifelse(prevented, 0, ev$loss * (1 - r_s[ev$year]))

  before <- as.numeric(tapply(ev$loss, factor(ev$year, levels = seq_len(n_years)), sum))
  after  <- as.numeric(tapply(loss_after, factor(ev$year, levels = seq_len(n_years)), sum))
  before[is.na(before)] <- 0
  after[is.na(after)] <- 0
  avoided <- before - after

  ci <- bootstrap_mean_ci(avoided)
  list(
    row = data.frame(
      control = ctl$control,
      scenario = ctl$scenario,
      annual_cost = ctl$annual_cost,
      ale_before = mean(before),
      ale_after = mean(after),
      avoided_mean = mean(avoided),
      avoided_ci_low = ci[1],
      avoided_ci_high = ci[2],
      rosi = (mean(avoided) - ctl$annual_cost) / ctl$annual_cost,
      p_year_pays_back = mean(avoided > ctl$annual_cost)
    ),
    avoided = data.frame(control = ctl$control, avoided = avoided, cost = ctl$annual_cost)
  )
})
roi <- do.call(rbind, lapply(results, `[[`, "row"))
write.csv(roi, "outputs/control_roi.csv", row.names = FALSE)
print(roi)

dist <- do.call(rbind, lapply(results, `[[`, "avoided"))
p <- ggplot(subset(dist, avoided > 0), aes(avoided)) +
  geom_histogram(bins = 60, fill = "#2b6cb0", colour = "white") +
  geom_vline(aes(xintercept = cost), colour = "#e53e3e", linetype = 2) +
  facet_wrap(~control, ncol = 1, scales = "free_y") +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  labs(title = "Loss avoided per year by each control",
       subtitle = "Years with a loss event; red dashed line = annual cost of the control",
       x = "Loss avoided in a simulated year (log scale)", y = "Simulated years") +
  theme_minimal(base_size = 12)
save_plot(p, "control_loss_avoided.png", 8, 7)

tbl <- data.frame(
  Control = roi$control,
  Scenario = roi$scenario,
  `Annual cost` = dollars(roi$annual_cost),
  `ALE before` = dollars(roi$ale_before),
  `ALE after` = dollars(roi$ale_after),
  `Loss avoided / yr (Monte Carlo 95% CI)` = paste0(dollars(roi$avoided_mean), " (",
                                        dollars(roi$avoided_ci_low), " – ",
                                        dollars(roi$avoided_ci_high), ")"),
  ROSI = sprintf("%+.0f%%", 100 * roi$rosi),
  `Years it pays back` = sprintf("%.0f%%", 100 * roi$p_year_pays_back),
  check.names = FALSE
)
report_add("## 3. Control ROI\n\n",
           paste(md_table(tbl), collapse = "\n"), "\n\n",
           "*Years it pays back* is the share of simulated years in which the loss avoided ",
           "that year exceeds the control's cost. A control can have a strongly positive ",
           "expected ROSI and still \"lose money\" in most individual years, because its ",
           "value comes from the rare bad year.\n\n",
           "The interval is a bootstrap over simulated years, so it measures Monte Carlo ",
           "noise in the mean: how much another seed would move it. It is not uncertainty ",
           "about how well the control works. Effectiveness is redrawn from its triangular ",
           "range every simulated year, so that uncertainty is averaged into the mean, not ",
           "reflected in the interval's width.\n\n",
           "![Loss avoided](figures/control_loss_avoided.png)\n")
