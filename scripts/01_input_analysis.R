# Input analysis: which distributions describe incident frequency and loss severity?
# Uses synthetic "history" (48 months of incident counts, 60 past BEC losses) so the
# repository runs without private data. Swap in real records with the same columns.

library(MASS)
library(ggplot2)

set.seed(2022)
dir.create("data/generated", showWarnings = FALSE, recursive = TRUE)

# ---- Synthetic history ------------------------------------------------------
# Generated from a negative binomial on purpose: the test below should prefer it,
# but 48 months is too little history to tell.
NB_MU <- 1.2
NB_SIZE <- 2.5
monthly <- data.frame(month = seq(as.Date("2018-01-01"), by = "month", length.out = 48),
                      incidents = rnbinom(48, mu = NB_MU, size = NB_SIZE))
bec <- read.csv("data/assumptions/scenarios.csv")
bec <- bec[bec$scenario == "Business email compromise", ]
bec_par <- lognormal_from_ci(bec$loss_p05, bec$loss_p95)
losses <- data.frame(loss_usd = round(rlnorm(60, bec_par$meanlog, bec_par$sdlog), -2))
write.csv(monthly, "data/generated/monthly_incidents.csv", row.names = FALSE)
write.csv(losses, "data/generated/bec_loss_history.csv", row.names = FALSE)

# ---- Frequency: Poisson vs. negative binomial --------------------------------
x <- monthly$incidents
fit_pois <- fitdistr(x, "Poisson")
fit_nb   <- fitdistr(x, "negative binomial")

# chi-square goodness of fit on binned counts 0, 1, 2, 3+
bins <- function(v) table(factor(pmin(v, 3), levels = 0:3))
expected_probs <- function(dfun) {
  p <- dfun(0:2)
  c(p, 1 - sum(p))
}
p_pois <- expected_probs(function(k) dpois(k, fit_pois$estimate["lambda"]))
p_nb   <- expected_probs(function(k) dnbinom(k, size = fit_nb$estimate["size"],
                                             mu = fit_nb$estimate["mu"]))
chisq_p <- function(p, n_params) {
  obs <- bins(x)
  stat <- sum((obs - length(x) * p)^2 / (length(x) * p))
  pchisq(stat, df = length(obs) - 1 - n_params, lower.tail = FALSE)
}
freq_table <- data.frame(
  model = c("Poisson", "Negative binomial"),
  AIC = round(c(AIC(fit_pois), AIC(fit_nb)), 1),
  chisq_p_value = round(c(chisq_p(p_pois, 1), chisq_p(p_nb, 2)), 3)
)
dispersion <- var(x) / mean(x)
print(freq_table)

# ---- Severity: which family fits past BEC losses? ----------------------------
y <- losses$loss_usd / 1000  # fit in $ thousands for numerical stability
candidates <- list(
  lognormal   = fitdistr(y, "lognormal"),
  gamma       = suppressWarnings(fitdistr(y, "gamma", start = list(shape = 1, rate = 1 / mean(y)),
                                          lower = c(1e-3, 1e-6))),
  weibull     = suppressWarnings(fitdistr(y, "weibull", lower = c(1e-3, 1e-3))),
  exponential = fitdistr(y, "exponential")
)
cdf <- list(
  lognormal   = function(q, e) plnorm(q, e["meanlog"], e["sdlog"]),
  gamma       = function(q, e) pgamma(q, e["shape"], e["rate"]),
  weibull     = function(q, e) pweibull(q, e["shape"], e["scale"]),
  exponential = function(q, e) pexp(q, e["rate"])
)
sev_table <- do.call(rbind, lapply(names(candidates), function(nm) {
  f <- candidates[[nm]]
  ks <- suppressWarnings(ks.test(y, function(q) cdf[[nm]](q, f$estimate)))
  data.frame(distribution = nm, AIC = round(AIC(f), 1),
             KS_statistic = round(unname(ks$statistic), 3))
}))
sev_table <- sev_table[order(sev_table$AIC), ]
print(sev_table)

best <- candidates$lognormal$estimate
fitted_ci <- exp(best["meanlog"] + c(-1, 1) * qnorm(0.95) * best["sdlog"]) * 1000

qq <- data.frame(empirical = sort(y),
                 theoretical = qlnorm(ppoints(length(y)), best["meanlog"], best["sdlog"]))
p <- ggplot(qq, aes(theoretical, empirical)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey50", linetype = 2) +
  geom_point(colour = "#2b6cb0") +
  scale_x_log10(labels = scales::label_dollar(suffix = "k")) +
  scale_y_log10(labels = scales::label_dollar(suffix = "k")) +
  labs(title = "BEC loss severity: lognormal Q-Q plot",
       subtitle = "60 historical losses vs. fitted lognormal (log scales)",
       x = "Theoretical quantile", y = "Observed loss") +
  theme_minimal(base_size = 12)
save_plot(p, "severity_qq_lognormal.png", 6, 5)

preferred <- freq_table$model[which.min(freq_table$AIC)]
both_fit <- all(freq_table$chisq_p_value > 0.05)
freq_note <- paste0(
  "Variance/mean = ", sprintf("%.2f", dispersion),
  " (a Poisson process gives about 1). AIC prefers the ", preferred, " model",
  if (both_fit) paste0(", and the chi-square test rejects neither: with only ",
                       length(x), " months of data the extra negative-binomial parameter ",
                       "isn't justified yet. Re-test as history accumulates.")
  else ".",
  if (preferred == "Poisson") paste0(
    " The synthetic history was in fact drawn from a negative binomial (true variance/mean = ",
    sprintf("%.2f", 1 + NB_MU / NB_SIZE), "), so this is a miss, not a confirmation: ",
    length(x), " months of counts can't reveal moderate overdispersion, and a Poisson model ",
    "built on them would understate how clustered incidents are."))

report_add("## 1. Input analysis\n\n",
           "**Frequency (48 months of incident counts).** ", freq_note, "\n\n",
           paste(md_table(freq_table), collapse = "\n"), "\n\n",
           "**Severity (60 past BEC losses).** Ranked by AIC:\n\n",
           paste(md_table(sev_table), collapse = "\n"), "\n\n",
           "The fitted lognormal implies a 90% interval of ",
           dollars(fitted_ci[1]), " to ", dollars(fitted_ci[2]),
           " per event, against the analyst's calibrated ",
           dollars(bec$loss_p05), " to ", dollars(bec$loss_p95), ".\n\n",
           "![Q-Q plot](figures/severity_qq_lognormal.png)\n")
