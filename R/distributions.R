# Sampling helpers written in base R so the project has no extra dependencies.

# Triangular distribution by inverse CDF (min a, mode c, max b).
rtriangle <- function(n, a, c, b) {
  stopifnot(a <= c, c <= b, a < b)
  u <- runif(n)
  fc <- (c - a) / (b - a)
  ifelse(u < fc,
         a + sqrt(u * (b - a) * (c - a)),
         b - sqrt((1 - u) * (b - a) * (b - c)))
}

# Lognormal parameters from a calibrated 90% interval (5th and 95th percentiles)
# the usual way analysts express "a single loss is between $X and $Y".
lognormal_from_ci <- function(p05, p95) {
  z <- qnorm(0.95)
  list(meanlog = (log(p05) + log(p95)) / 2,
       sdlog   = (log(p95) - log(p05)) / (2 * z))
}

dollars <- function(x, digits = 0) {
  paste0("$", formatC(x, format = "f", big.mark = ",", digits = digits))
}

# Dollars to `sig` significant figures with a k/M suffix ($1.20M, $338k), for
# figures that the Monte Carlo error doesn't support to the dollar.
dollars_sig <- function(x, sig = 3) {
  vapply(x, function(v) {
    unit <- if (abs(v) >= 1e6) c(1e6, "M") else if (abs(v) >= 1e3) c(1e3, "k") else c(1, "")
    scaled <- signif(v, sig) / as.numeric(unit[1])
    decimals <- max(0, sig - 1 - floor(log10(max(abs(scaled), 1e-12))))
    paste0("$", formatC(scaled, format = "f", digits = decimals), unit[2])
  }, character(1))
}
