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
