# Risk tolerance: is the loss exceedance curve inside the organization's appetite,
# before and after the proposed controls?
# The tolerance curve (data/assumptions/tolerance.csv) is the board's statement of
# the most it will accept, e.g. "no more than a 10% chance of losing over $2.5M in a
# year". Between the stated points it is interpolated on log-log scales.
# Residual risk reuses the same simulated years and control draws as script 03.

library(ggplot2)

events    <- readRDS("outputs/events.rds")
scenarios <- read.csv("data/assumptions/scenarios.csv")
tolerance <- read.csv("data/assumptions/tolerance.csv")
validate_inputs(scenarios, tolerance = tolerance)
avoided   <- readRDS("outputs/combined_avoided_by_year.rds")

before <- rowSums(annual_losses(events, scenarios))
after  <- before - avoided  # controls on one scenario compound (script 03)
n_years <- length(before)
tolerated <- function(x) {
  exp(approx(log(tolerance$loss), log(tolerance$max_probability), log(x), rule = 1)$y)
}

# ---- At the stated points -----------------------------------------------------------
p_before <- exceedance(before, tolerance$loss)
p_after  <- exceedance(after, tolerance$loss)
binom_se <- function(p) sqrt(p * (1 - p) / n_years)
check <- data.frame(
  loss = tolerance$loss,
  max_probability = tolerance$max_probability,
  p_before = p_before, se_before = binom_se(p_before),
  p_after = p_after, se_after = binom_se(p_after)
)
write.csv(check, "outputs/tolerance_check.csv", row.names = FALSE)
print(check)

# ---- Along the whole curve -----------------------------------------------------------
grid <- 10^seq(log10(min(tolerance$loss)), log10(max(tolerance$loss)), length.out = 400)
over <- function(v) {
  above <- exceedance(v, grid) > tolerated(grid)
  if (!any(above)) return(c(NA, NA))
  range(grid[above])
}
over_before <- over(before)
over_after  <- over(after)

# ---- Figure: tail on log-probability axis -------------------------------------------
x_grid <- 10^seq(5.3, 7.7, length.out = 300)
curves <- rbind(
  data.frame(curve = "Today", loss = x_grid, p = exceedance(before, x_grid)),
  data.frame(curve = "With the proposed controls", loss = x_grid, p = exceedance(after, x_grid))
)
curves <- subset(curves, p > 0)
tol_df <- data.frame(loss = tolerance$loss, p = tolerance$max_probability)
p <- ggplot() +
  geom_line(data = tol_df, aes(loss, p), colour = "#e53e3e", linewidth = 1, linetype = 2) +
  geom_point(data = tol_df, aes(loss, p), colour = "#e53e3e", size = 2.2) +
  geom_step(data = curves, aes(loss, p, colour = curve), linewidth = 0.9) +
  annotate("text", x = max(tolerance$loss), y = min(tolerance$max_probability) * 1.8,
           label = "risk tolerance", colour = "#e53e3e", hjust = 0.5, size = 3.4) +
  scale_colour_manual(values = c("Today" = "black", "With the proposed controls" = "#2b6cb0")) +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  scale_y_log10(labels = scales::label_percent(accuracy = 0.01),
                breaks = c(0.5, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0.0005, 0.0002)) +
  labs(title = "The tail: loss exceedance vs. risk tolerance",
       subtitle = sprintf(paste("P(annual loss > x), log scales. With %s simulated years,",
                                "probabilities below\nabout 0.05%% rest on a handful of years."),
                          format(n_years, big.mark = ",")),
       x = "Annual loss", y = "P(annual loss > x)", colour = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")
save_plot(p, "loss_exceedance_tolerance.png", 9, 5.5)

# ---- Report -----------------------------------------------------------------------------
fmt_p <- function(p, se) sprintf("%.2f%% ± %.2f", 100 * p, 100 * se)
verdict <- function(p) ifelse(p <= tolerance$max_probability, "within", "**exceeds**")
check_fmt <- data.frame(
  `Annual loss over` = dollars_sig(tolerance$loss, 2),
  `Tolerated probability` = sprintf("%.1f%%", 100 * tolerance$max_probability),
  `Today` = paste(fmt_p(p_before, check$se_before), verdict(p_before)),
  `With the proposed controls` = paste(fmt_p(p_after, check$se_after), verdict(p_after)),
  check.names = FALSE
)
describe_over <- function(r) {
  if (is.na(r[1])) return("stays inside the tolerance curve everywhere it is defined")
  sprintf("is above the tolerance curve for annual losses between about %s and %s",
          dollars_sig(r[1], 2), dollars_sig(r[2], 2))
}
report_add("## 5. Risk tolerance\n\n",
           "An illustrative risk appetite (`data/assumptions/tolerance.csv`), checked against ",
           "the simulated total annual loss. ± is one binomial standard error in percentage ",
           "points.\n\n",
           paste(md_table(check_fmt), collapse = "\n"), "\n\n",
           "Between the stated points the tolerance is interpolated on log-log scales. On ",
           "that curve, today's loss exceedance curve ", describe_over(over_before),
           ". With the proposed controls it ", describe_over(over_after), ".\n\n",
           "![Loss exceedance vs. tolerance](figures/loss_exceedance_tolerance.png)\n")

saveRDS(list(over_before = over_before, over_after = over_after),
        "outputs/tolerance_overlap.rds")
