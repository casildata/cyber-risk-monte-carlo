# Return on security investment (ROSI) for candidate controls.
# Each control is applied to the SAME simulated events from script 02:
#   - frequency reduction r_f: each event is prevented with probability r_f
#     (thinning a Poisson process gives exactly Poisson(lambda * (1 - r_f)))
#   - severity reduction r_s: surviving events cost (1 - r_s) as much
# Both reductions are uncertain (triangular per simulated year).
# ROSI = (ALE before - ALE after - annual cost) / annual cost.
#
# The second half asks a different question: given that we don't know the true
# event rate or how well the control works, how sure are we that it pays off?
# That needs uncertainty held fixed across years (two-level), not redrawn yearly.

library(ggplot2)

set.seed(99)
events    <- readRDS("outputs/events.rds")
scenarios <- read.csv("data/assumptions/scenarios.csv")
controls  <- read.csv("data/assumptions/controls.csv")
validate_inputs(scenarios, controls)
n_years   <- attr(events, "n_years")

bootstrap_mean_ci <- function(v, B = 2000) {
  means <- replicate(B, mean(sample(v, replace = TRUE)))
  unname(quantile(means, c(0.025, 0.975)))
}

results <- lapply(seq_len(nrow(controls)), function(i) {
  ctl <- controls[i, ]
  ev  <- events[events$scenario == ctl$scenario, ]
  r_f <- rtriangle(n_years, ctl$freq_red_min, ctl$freq_red_mode, ctl$freq_red_max)
  r_s <- rtriangle(n_years, ctl$sev_red_min, ctl$sev_red_mode, ctl$sev_red_max)
  yr  <- apply_control(ev, r_f, r_s, n_years)

  ci <- bootstrap_mean_ci(yr$avoided)
  list(
    row = data.frame(
      control = ctl$control,
      scenario = ctl$scenario,
      annual_cost = ctl$annual_cost,
      ale_before = mean(yr$before),
      ale_after = mean(yr$after),
      avoided_mean = mean(yr$avoided),
      avoided_ci_low = ci[1],
      avoided_ci_high = ci[2],
      rosi = (mean(yr$avoided) - ctl$annual_cost) / ctl$annual_cost,
      p_year_pays_back = mean(yr$avoided > ctl$annual_cost)
    ),
    avoided = data.frame(control = ctl$control, avoided = yr$avoided, cost = ctl$annual_cost)
  )
})
roi <- do.call(rbind, lapply(results, `[[`, "row"))
write.csv(roi, "outputs/control_roi.csv", row.names = FALSE)
print(roi)

dist <- do.call(rbind, lapply(results, `[[`, "avoided"))
# loss avoided per simulated year, one column per control, for script 05
saveRDS(sapply(split(dist$avoided, factor(dist$control, levels = controls$control)), identity),
        "outputs/control_avoided_by_year.rds")

# the histogram leaves out years with nothing avoided, so give their count in each title
zero_years <- tapply(dist$avoided == 0, dist$control, sum)
panel_title <- setNames(sprintf("%s  (+ %s years with $0 avoided, not shown)", names(zero_years),
                                format(zero_years, big.mark = ",", trim = TRUE)),
                        names(zero_years))
p <- ggplot(subset(dist, avoided > 0), aes(avoided)) +
  geom_histogram(bins = 60, fill = "#2b6cb0", colour = "white") +
  geom_vline(aes(xintercept = cost), colour = "#e53e3e", linetype = 2) +
  facet_wrap(~control, ncol = 1, scales = "free_y", labeller = as_labeller(panel_title)) +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  labs(title = "Loss avoided per year by each control",
       subtitle = "Years with a loss event; red dashed line = annual cost of the control",
       x = "Loss avoided in a simulated year (log scale)", y = "Simulated years") +
  theme_minimal(base_size = 12)
save_plot(p, "control_loss_avoided.png", 8, 7)

# ---- Two-level uncertainty: will the control pay off? -------------------------------
# Outer level: draw what we don't know once (the long-run event rate lambda, and the
# control's r_f and r_s) and hold it fixed. Inner level: the expected loss avoided per
# year given those, which has a closed form (R/model.R: control_uncertainty).
# A second version holds lambda at its expected value, to show how much of the
# uncertainty comes from the event rate rather than from the control itself.
N_DRAWS <- 10000
set.seed(2026)
uncert <- lapply(seq_len(nrow(controls)), function(i) {
  ctl <- controls[i, ]
  s <- scenarios[scenarios$scenario == ctl$scenario, ]
  u <- control_uncertainty(ctl, s, N_DRAWS)
  rosi_rate_known <- (lef_mean(s) *expected_event_loss(s) * (1 - (1 - u$r_f) * (1 - u$r_s)) -
                        ctl$annual_cost) / ctl$annual_cost
  list(
    row = data.frame(
      control = ctl$control,
      avoided_p05 = unname(quantile(u$avoided, 0.05)),
      avoided_p95 = unname(quantile(u$avoided, 0.95)),
      rosi_p05 = unname(quantile(u$rosi, 0.05)),
      rosi_median = median(u$rosi),
      rosi_p95 = unname(quantile(u$rosi, 0.95)),
      p_rosi_negative = mean(u$rosi < 0),
      p_rosi_negative_rate_known = mean(rosi_rate_known < 0)
    ),
    draws = data.frame(control = ctl$control, rosi = u$rosi)
  )
})
uncert_tbl <- do.call(rbind, lapply(uncert, `[[`, "row"))
write.csv(uncert_tbl, "outputs/control_rosi_uncertainty.csv", row.names = FALSE)
print(uncert_tbl)

rosi_draws <- do.call(rbind, lapply(uncert, `[[`, "draws"))
rosi_draws$control <- factor(rosi_draws$control, levels = controls$control)
p_neg <- data.frame(control = factor(controls$control, levels = controls$control),
                    label = sprintf("P(ROSI < 0) = %.1f%%", 100 * uncert_tbl$p_rosi_negative))
p2 <- ggplot(rosi_draws, aes(rosi)) +
  geom_histogram(aes(fill = rosi < 0), bins = 80, colour = NA, boundary = 0) +
  geom_vline(xintercept = 0, colour = "grey20") +
  geom_text(data = p_neg, aes(x = Inf, y = Inf, label = label), hjust = 1.05, vjust = 1.5,
            size = 3.4) +
  facet_wrap(~control, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c(`FALSE` = "#2b6cb0", `TRUE` = "#e53e3e"), guide = "none") +
  scale_x_continuous(labels = scales::label_percent()) +
  labs(title = "How sure are we that each control pays off?",
       subtitle = sprintf(paste("Expected ROSI over %s draws of the event rate and the",
                                "control's effectiveness.\nRed: the control loses money."),
                          format(N_DRAWS, big.mark = ",")),
       x = "Expected return on security investment", y = "Draws") +
  theme_minimal(base_size = 12)
save_plot(p2, "control_rosi_uncertainty.png", 8, 7)

pct <- function(x) sprintf("%+.0f%%", 100 * x)
tbl <- data.frame(
  Control = roi$control,
  Scenario = roi$scenario,
  `Annual cost` = dollars(roi$annual_cost),
  `Loss avoided / yr (90% uncertainty band)` = paste0(dollars_sig(roi$avoided_mean), " (",
                                                      dollars_sig(uncert_tbl$avoided_p05), " – ",
                                                      dollars_sig(uncert_tbl$avoided_p95), ")"),
  `ROSI (90% band)` = paste0(pct(roi$rosi), " (", pct(uncert_tbl$rosi_p05), " to ",
                             pct(uncert_tbl$rosi_p95), ")"),
  `P(ROSI < 0)` = sprintf("%.1f%%", 100 * uncert_tbl$p_rosi_negative),
  `Years it pays back` = sprintf("%.0f%%", 100 * roi$p_year_pays_back),
  check.names = FALSE
)
mc_tbl <- data.frame(
  Control = roi$control,
  `ALE before` = dollars(roi$ale_before),
  `ALE after` = dollars(roi$ale_after),
  `Loss avoided / yr (Monte Carlo 95% CI)` = paste0(dollars(roi$avoided_mean), " (",
                                                    dollars(roi$avoided_ci_low), " – ",
                                                    dollars(roi$avoided_ci_high), ")"),
  `P(ROSI < 0) if the event rate were known` =
    sprintf("%.1f%%", 100 * uncert_tbl$p_rosi_negative_rate_known),
  check.names = FALSE
)
report_add("## 3. Control ROI\n\n",
           paste(md_table(tbl), collapse = "\n"), "\n\n",
           "**Two kinds of uncertainty.** The expected ROSI averages over everything, ",
           "including what we don't know. The 90% band and P(ROSI < 0) come from a two-level ",
           "analysis: the long-run event rate and the control's effectiveness are drawn ",
           "once and held fixed (", format(N_DRAWS, big.mark = ","), " draws), and the ",
           "expected loss avoided is computed for each draw. P(ROSI < 0) is the chance that, ",
           "given what we don't know, the control costs more than it saves on average. ",
           "Severity parameters are treated as known, so the bands are if anything too narrow.\n\n",
           "*Years it pays back* is the share of simulated years in which the loss avoided ",
           "that year exceeds the control's cost. A control can have a strongly positive ",
           "expected ROSI and still \"lose money\" in most individual years, because its ",
           "value comes from the rare bad year. For EDR it is close to the share of years ",
           "with any ransomware event.\n\n",
           "![ROSI uncertainty](figures/control_rosi_uncertainty.png)\n\n",
           "**Monte Carlo detail.** The interval below is a bootstrap over simulated years: ",
           "how far another seed would move the mean, not uncertainty about the control. ",
           "The last column holds the event rate at its expected value, so the remaining ",
           "risk of losing money comes from the control's effectiveness alone.\n\n",
           paste(md_table(mc_tbl), collapse = "\n"), "\n\n",
           if (all(uncert_tbl$p_rosi_negative_rate_known < 0.001))
             paste0("With the event rate known, no control loses money even at the bottom of ",
                    "its effectiveness range. The risk of a negative return comes from not ",
                    "knowing how often the scenario happens, so a better frequency estimate ",
                    "(see section 4) is worth more here than a better effectiveness estimate.\n\n"),
           "![Loss avoided](figures/control_loss_avoided.png)\n")
