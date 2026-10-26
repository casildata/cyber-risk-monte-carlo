one_scenario <- data.frame(scenario = "Ransomware", lef_min = 0.05, lef_mode = 0.15,
                           lef_max = 0.40, loss_p05 = 2.5e5, loss_p95 = 5e6)

test_that("simulated ALE matches the closed form within 4 Monte Carlo standard errors", {
  set.seed(1)
  n <- 50000
  ann <- annual_losses(simulate_events(one_scenario, n), one_scenario)[, 1]
  exact <- lef_mean(one_scenario) * expected_event_loss(one_scenario)
  expect_lt(abs(mean(ann) - exact), 4 * sd(ann) / sqrt(n))
})

test_that("years without events are kept, including trailing ones", {
  ev <- data.frame(scenario = "R", year = c(1, 1, 3), loss = c(10, 20, 5))
  attr(ev, "n_years") <- 5
  m <- annual_losses(ev, data.frame(scenario = "R"))
  expect_equal(m[, 1], c(30, 0, 5, 0, 0))
})

test_that("a control that does nothing avoids nothing; a perfect one avoids everything", {
  ev <- data.frame(scenario = "R", year = c(1, 1, 3), loss = c(10, 20, 5))
  expect_equal(sum(apply_control(ev, r_f = 0, r_s = 0, n_years = 4)$avoided), 0)
  expect_equal(sum(apply_control(ev, r_f = 1, r_s = 0, n_years = 4)$avoided), 35)
  expect_equal(apply_control(ev, r_f = 0, r_s = 0.5, n_years = 4)$after, c(15, 0, 2.5, 0))
})

test_that("the loss cap limits every single loss, and its expected value matches", {
  set.seed(2)
  ev <- simulate_events(one_scenario, 50000, loss_cap = 1e6)
  expect_lte(max(ev$loss), 1e6)
  expect_equal(mean(ev$loss), expected_event_loss(one_scenario, loss_cap = 1e6), tolerance = 0.02)
})

test_that("a per-scenario loss_cap column overrides the default", {
  s <- transform(one_scenario, loss_cap = 2e6)
  set.seed(3)
  expect_lte(max(simulate_events(s, 20000)$loss), 2e6)
})

test_that("two-level draws average to the same expected loss avoided", {
  ctl <- data.frame(freq_red_min = 0.3, freq_red_mode = 0.5, freq_red_max = 0.7,
                    sev_red_min = 0.3, sev_red_mode = 0.5, sev_red_max = 0.7, annual_cost = 1e5)
  set.seed(4)
  u <- control_uncertainty(ctl, one_scenario, 1e5)
  # E[lambda] E[L] (1 - E[1 - r_f] E[1 - r_s]), since the draws are independent
  exact <- lef_mean(one_scenario) * expected_event_loss(one_scenario) * (1 - 0.5 * 0.5)
  expect_equal(mean(u$avoided), exact, tolerance = 0.01)
  expect_equal(u$rosi, (u$avoided - 1e5) / 1e5)
})

test_that("exceedance gives P(X > x)", {
  v <- c(1, 2, 2, 3, 10)
  expect_equal(exceedance(v, c(0, 2, 2.5, 10)), c(1, 0.4, 0.4, 0))
})

test_that("controls on the same scenario compound instead of adding up", {
  ev <- data.frame(scenario = "R", year = c(1, 1, 3), loss = c(10, 20, 5))
  half <- attr(apply_control(ev, r_f = 0, r_s = 0.5, n_years = 3), "factor")
  # two controls that each halve every loss leave a quarter, so 75% is avoided
  expect_equal(combined_avoided(ev, list(1:3, 1:3), list(half, half), 3), c(22.5, 0, 3.75))
  # two perfect controls avoid the loss once, not twice
  stop_all <- attr(apply_control(ev, r_f = 1, r_s = 0, n_years = 3), "factor")
  expect_equal(combined_avoided(ev, list(1:3, 1:3), list(stop_all, stop_all), 3), c(30, 0, 5))
  # on different events, the combined effect is the sum
  expect_equal(combined_avoided(ev, list(1:2, 3), list(half[1:2], stop_all[3]), 3), c(15, 0, 5))
})

test_that("severity uncertainty widens the band without moving the mean", {
  ctl <- data.frame(freq_red_min = 0.3, freq_red_mode = 0.5, freq_red_max = 0.7,
                    sev_red_min = 0.3, sev_red_mode = 0.5, sev_red_max = 0.7, annual_cost = 1e5)
  set.seed(5)
  known <- control_uncertainty(ctl, one_scenario, 1e5)
  set.seed(5)
  wide <- control_uncertainty(ctl, transform(one_scenario, loss_uncertainty = 1.5), 1e5)
  expect_true(all(known$m == 1))
  # 90% of multipliers between 1/1.5 and 1.5, shifted down so the mean stays 1
  sdlog <- log(1.5) / qnorm(0.95)
  expect_equal(quantile(wide$m, c(0.05, 0.95), names = FALSE),
               c(1 / 1.5, 1.5) * exp(-sdlog^2 / 2), tolerance = 0.02)
  expect_equal(mean(wide$avoided), mean(known$avoided), tolerance = 0.01)
  expect_gt(sd(wide$avoided), sd(known$avoided))
})

test_that("EVPI is zero when the decision is certain and positive when it is not", {
  expect_equal(evpi(c(10, 20, 30)), 0)
  expect_equal(evpi(c(-10, -20)), 0)
  # buy now: mean 5; choose per draw: mean(30, 0) = 15
  expect_equal(evpi(c(30, -20)), 10)
})

test_that("double extortion adds breach events but keeps the breach frequency", {
  two <- rbind(one_scenario,
               data.frame(scenario = "Customer data breach", lef_min = 0.10, lef_mode = 0.30,
                          lef_max = 0.80, loss_p05 = 1e5, loss_p95 = 3e6))
  n <- 50000
  set.seed(6)
  base <- simulate_events(two, n)
  set.seed(6)
  dex <- simulate_events(two, n, p_ext = 0.3)
  rate <- function(ev) sum(ev$scenario == "Customer data breach") / n
  expect_equal(rate(dex), rate(base), tolerance = 0.03)
  # ransomware years now come with more breach losses
  both <- function(ev) {
    m <- annual_losses(ev, two) > 0
    mean(m[m[, 1], 2])
  }
  expect_gt(both(dex), both(base) + 0.05)
  expect_error(simulate_events(two, 10, p_ext = 0.9), "p_ext too large")
})

test_that("lambda_draws replaces the estimate with resampled rates", {
  set.seed(7)
  ev <- simulate_events(one_scenario, 50000, lambda_draws = list(Ransomware = 2))
  expect_equal(nrow(ev) / 50000, 2, tolerance = 0.02)
})
