# The same model with inputs calibrated against public sources, next to the
# illustrative run. data/assumptions/scenarios_calibrated.csv describes a mid-size
# US critical-infrastructure operator (about $500M revenue, 2,000 employees); each
# row names its sources and a confidence level, and docs/calibration.md shows the
# arithmetic. Controls, tolerance and seed are the same as in the illustrative run.

library(ggplot2)

N_YEARS <- 20000
set.seed(1234)

illus      <- read.csv("data/assumptions/scenarios.csv")
calibrated <- read.csv("data/assumptions/scenarios_calibrated.csv")
controls   <- read.csv("data/assumptions/controls.csv")
tolerance  <- read.csv("data/assumptions/tolerance.csv")
validate_inputs(calibrated, controls, tolerance)

events <- simulate_events(calibrated, N_YEARS)
annual <- annual_losses(events, calibrated)
total  <- rowSums(annual)
illus_annual <- annual_losses(readRDS("outputs/events.rds"), illus)
illus_total  <- rowSums(illus_annual)

# Year-by-scenario losses in the same format as script 02's export, for tail-risk
# budget optimization (release v1.1)
write.csv(data.frame(year = seq_len(N_YEARS), round(annual), Total = round(total),
                     check.names = FALSE),
          gzfile("outputs/annual_loss_calibrated_by_year.csv.gz"), row.names = FALSE)

# ---- Per scenario: illustrative vs. calibrated -------------------------------------
by_scenario <- data.frame(
  scenario = c(calibrated$scenario, "Total"),
  confidence = c(calibrated$confidence, ""),
  ale_illustrative = c(colMeans(illus_annual)[calibrated$scenario], mean(illus_total)),
  ale_calibrated = c(colMeans(annual), mean(total)),
  p95_illustrative = c(apply(illus_annual[, calibrated$scenario], 2, quantile, 0.95),
                       quantile(illus_total, 0.95)),
  p95_calibrated = c(apply(annual, 2, quantile, 0.95), quantile(total, 0.95)),
  row.names = NULL
)
totals <- data.frame(
  run = c("Illustrative", "Calibrated"),
  ale = c(mean(illus_total), mean(total)),
  p95 = c(quantile(illus_total, 0.95), quantile(total, 0.95)),
  p99 = c(quantile(illus_total, 0.99), quantile(total, 0.99)),
  p_over_5m = c(mean(illus_total > 5e6), mean(total > 5e6))
)
write.csv(by_scenario, "outputs/calibrated_by_scenario.csv", row.names = FALSE)
write.csv(totals, "outputs/calibrated_totals.csv", row.names = FALSE)
print(by_scenario)
print(totals)

# ---- Tolerance, before and after the proposed controls ------------------------------------
# Controls applied to the calibrated events as in script 03 (thinning, same draws per
# control), combined as in script 05.
set.seed(99)
applied <- lapply(seq_len(nrow(controls)), function(i) {
  ctl <- controls[i, ]
  rows <- which(events$scenario == ctl$scenario)
  yr <- apply_control(events[rows, ],
                      rtriangle(N_YEARS, ctl$freq_red_min, ctl$freq_red_mode, ctl$freq_red_max),
                      rtriangle(N_YEARS, ctl$sev_red_min, ctl$sev_red_mode, ctl$sev_red_max),
                      N_YEARS)
  list(rows = rows, factor = attr(yr, "factor"))
})
total_after <- total - combined_avoided(events, lapply(applied, `[[`, "rows"),
                                        lapply(applied, `[[`, "factor"), N_YEARS)
tol_cal <- data.frame(loss = tolerance$loss, max_probability = tolerance$max_probability,
                      p_illustrative = exceedance(illus_total, tolerance$loss),
                      p_calibrated = exceedance(total, tolerance$loss),
                      p_calibrated_controls = exceedance(total_after, tolerance$loss))
write.csv(tol_cal, "outputs/calibrated_tolerance.csv", row.names = FALSE)

# ---- Controls under calibrated inputs ----------------------------------------------------
# Expected loss avoided in closed form (independent draws):
#   E[lambda] * E[L] * (1 - (1 - E[r_f]) * (1 - E[r_s]))
# and the two-level draws for P(ROSI < 0) and EVPI, as in script 03.
tri_mean <- function(a, m, b) (a + m + b) / 3
N_DRAWS <- 10000
set.seed(2026)
ctl_cal <- do.call(rbind, lapply(seq_len(nrow(controls)), function(i) {
  ctl <- controls[i, ]
  s <- calibrated[calibrated$scenario == ctl$scenario, ]
  avoided <- lef_mean(s) * expected_event_loss(s) *
    (1 - (1 - tri_mean(ctl$freq_red_min, ctl$freq_red_mode, ctl$freq_red_max)) *
       (1 - tri_mean(ctl$sev_red_min, ctl$sev_red_mode, ctl$sev_red_max)))
  u <- control_uncertainty(ctl, s, N_DRAWS)
  data.frame(control = ctl$control, scenario = ctl$scenario, annual_cost = ctl$annual_cost,
             avoided = avoided, rosi = (avoided - ctl$annual_cost) / ctl$annual_cost,
             p_rosi_negative = mean(u$rosi < 0), evpi = evpi(u$avoided - ctl$annual_cost))
}))
write.csv(ctl_cal, "outputs/calibrated_controls.csv", row.names = FALSE)
print(ctl_cal)

# ---- Figure: both loss exceedance curves against the tolerance ----------------------------
x_grid <- 10^seq(5, 7.7, length.out = 300)
curves <- rbind(
  data.frame(curve = "Illustrative inputs", loss = x_grid, p = exceedance(illus_total, x_grid)),
  data.frame(curve = "Calibrated inputs", loss = x_grid, p = exceedance(total, x_grid))
)
curves <- subset(curves, p > 0)
curves$curve <- factor(curves$curve, levels = c("Illustrative inputs", "Calibrated inputs"))
tol_df <- data.frame(loss = tolerance$loss, p = tolerance$max_probability)
p <- ggplot() +
  geom_line(data = tol_df, aes(loss, p), colour = "#e53e3e", linewidth = 1, linetype = 2) +
  geom_point(data = tol_df, aes(loss, p), colour = "#e53e3e", size = 2.2) +
  geom_step(data = curves, aes(loss, p, colour = curve), linewidth = 0.9) +
  scale_colour_manual(values = c("Illustrative inputs" = "grey45", "Calibrated inputs" = "#2b6cb0")) +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  scale_y_log10(labels = scales::label_percent(accuracy = 0.01),
                breaks = c(0.5, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0.0005, 0.0002)) +
  labs(title = "Illustrative vs. calibrated inputs",
       subtitle = sprintf(paste("P(annual loss > x), log scales, %s simulated years each.",
                                "No controls; red dashed line: risk tolerance.\nCalibrated:",
                                "ransomware, BEC and data breach;",
                                "DDoS and insider misuse unchanged."),
                          format(N_YEARS, big.mark = ",")),
       x = "Annual loss", y = "P(annual loss > x)", colour = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")
save_plot(p, "loss_exceedance_calibrated.png", 9, 5.5)

# ---- Report -------------------------------------------------------------------------------
sc_fmt <- data.frame(
  Scenario = by_scenario$scenario,
  Confidence = by_scenario$confidence,
  `ALE, illustrative` = dollars_sig(by_scenario$ale_illustrative),
  `ALE, calibrated` = dollars_sig(by_scenario$ale_calibrated),
  `P95, illustrative` = dollars_sig(by_scenario$p95_illustrative),
  `P95, calibrated` = dollars_sig(by_scenario$p95_calibrated),
  check.names = FALSE
)
tot_fmt <- data.frame(
  Inputs = totals$run,
  `Total ALE` = dollars_sig(totals$ale),
  `P95 (1-in-20)` = dollars_sig(totals$p95),
  `P99 (1-in-100)` = dollars_sig(totals$p99),
  `P(> $5M)` = sprintf("%.1f%%", 100 * totals$p_over_5m),
  check.names = FALSE
)
verdict <- function(p) ifelse(p <= tolerance$max_probability, "within", "**exceeds**")
# ± one binomial standard error in percentage points, as in section 5
fmt_p <- function(p) paste(sprintf("%.2f%% ± %.2f", 100 * p, 100 * sqrt(p * (1 - p) / N_YEARS)),
                           verdict(p))
tol_fmt <- data.frame(
  `Annual loss over` = dollars_sig(tolerance$loss, 2),
  Tolerated = sprintf("%.1f%%", 100 * tolerance$max_probability),
  Illustrative = fmt_p(tol_cal$p_illustrative),
  Calibrated = fmt_p(tol_cal$p_calibrated),
  `Calibrated, with the proposed controls` = fmt_p(tol_cal$p_calibrated_controls),
  check.names = FALSE
)
ctl_fmt <- data.frame(
  Control = ctl_cal$control,
  `Annual cost` = dollars(ctl_cal$annual_cost),
  `Loss avoided / yr` = dollars_sig(ctl_cal$avoided),
  `Expected ROSI` = sprintf("%+.0f%%", 100 * ctl_cal$rosi),
  `P(ROSI < 0)` = sprintf("%.1f%%", 100 * ctl_cal$p_rosi_negative),
  `EVPI / yr` = dollars_sig(ctl_cal$evpi, 2),
  check.names = FALSE
)
report_add("## 6. Calibrated inputs\n\n",
           "The same model, controls and tolerance with `scenarios_calibrated.csv`: frequencies ",
           "and loss ranges sized for a mid-size US critical-infrastructure operator (about ",
           "$500M revenue) from public sources, with the derivation in ",
           "[calibration.md](calibration.md). Three scenarios are calibrated; DDoS outage and ",
           "insider misuse keep their illustrative values because no usable public figures ",
           "exist at this size. ", format(N_YEARS, big.mark = ","), " simulated years, same seed ",
           "as section 2.\n\n",
           paste(md_table(sc_fmt), collapse = "\n"), "\n\n",
           paste(md_table(tot_fmt), collapse = "\n"), "\n\n",
           "![Illustrative vs. calibrated](figures/loss_exceedance_calibrated.png)\n\n",
           "**Risk tolerance with calibrated inputs.** ± is one binomial standard error in percentage ",
           "points; an exceedance within about one standard error of the tolerance is not a clear ",
           "breach.\n\n",
           paste(md_table(tol_fmt), collapse = "\n"), "\n\n",
           "**Controls with calibrated inputs.** Same costs and effectiveness ranges as section 3 ",
           "(those are still illustrative). Loss avoided is the closed-form expectation; ",
           "P(ROSI < 0) and EVPI come from ", format(N_DRAWS, big.mark = ","),
           " two-level draws.\n\n",
           paste(md_table(ctl_fmt), collapse = "\n"), "\n")
