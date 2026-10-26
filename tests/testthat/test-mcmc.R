# Posterior for 8 incidents in 10 years with a Gamma(1, 0.01) prior: Gamma(9, 10.01)
log_target <- function(lambda) 8 * log(lambda) - 10.01 * lambda
target <- function(lambda) lambda^8 * exp(-10.01 * lambda)
exact_mean <- 9 / 10.01

test_that("the corrected sampler recovers the exact posterior mean", {
  set.seed(1)
  d <- mh_log_walk(20000, 5, 0.6, log_target)$draws[-(1:1000)]
  expect_equal(mean(d), exact_mean, tolerance = 0.02)
})

test_that("the truncated proposal is unbiased once the Hastings correction is added", {
  set.seed(2)
  ch <- mh_truncated(20000, 5, 1.4, target, accepted_only = FALSE, hastings = TRUE)
  expect_equal(mean(ch$draws[ch$iter > 1000]), exact_mean, tolerance = 0.02)
})

test_that("a correct sampler stores one draw per iteration; accepted-only stores fewer", {
  set.seed(3)
  expect_length(mh_log_walk(500, 1, 0.6, log_target)$draws, 500)
  expect_lt(length(mh_log_walk(500, 1, 0.6, log_target, accepted_only = TRUE)$draws), 500)
})

test_that("split R-hat is near 1 for agreeing chains and flags chains that disagree", {
  set.seed(4)
  same <- matrix(rnorm(4000), ncol = 4)
  expect_lt(split_rhat(same), 1.01)
  apart <- same + rep(c(0, 0, 0, 2), each = 1000)
  expect_gt(split_rhat(apart), 1.1)
  # a chain that drifts is caught by splitting it in half
  drift <- cbind(same[, 1:3], seq(-3, 3, length.out = 1000))
  expect_gt(split_rhat(drift), 1.05)
})

test_that("MCSE of independent draws is sd / sqrt(n)", {
  set.seed(5)
  x <- rnorm(10000)
  expect_equal(mcse_mean(x), sd(x) / 100, tolerance = 0.1)
})
