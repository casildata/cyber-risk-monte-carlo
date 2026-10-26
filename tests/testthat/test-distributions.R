test_that("lognormal_from_ci round-trips the analyst's interval", {
  p <- lognormal_from_ci(1e4, 4e5)
  expect_equal(qlnorm(c(0.05, 0.95), p$meanlog, p$sdlog), c(1e4, 4e5))
})

test_that("rtriangle respects its bounds and mean", {
  set.seed(1)
  x <- rtriangle(1e5, 0.05, 0.15, 0.40)
  expect_true(all(x >= 0.05 & x <= 0.40))
  expect_equal(mean(x), 0.2, tolerance = 0.01)
})

test_that("rpert respects its bounds and has mean (a + 4c + b) / 6", {
  set.seed(1)
  x <- rpert(1e5, 0.05, 0.15, 0.40)
  expect_true(all(x >= 0.05 & x <= 0.40))
  expect_equal(mean(x), (0.05 + 4 * 0.15 + 0.40) / 6, tolerance = 0.01)
})

test_that("dollars_sig rounds to significant figures with a unit", {
  expect_equal(dollars_sig(c(1204196, 337719, 90482, 950)), c("$1.20M", "$338k", "$90.5k", "$950"))
  expect_equal(dollars_sig(11400, 2), "$11k")
  expect_equal(dollars_sig(0), "$0")
})
