read_input <- function(f) read.csv(file.path("..", "..", "data", "assumptions", f))
scen <- read_input("scenarios.csv")
ctl <- read_input("controls.csv")
tol <- read_input("tolerance.csv")

test_that("the committed assumption files are valid", {
  expect_true(validate_inputs(scen, ctl, tol))
})

test_that("a misspelled scenario in controls.csv is an error, not ROSI = -100%", {
  expect_error(validate_inputs(scen, transform(ctl, scenario = "Ransomwre")),
               "scenario not found")
})

test_that("an out-of-order frequency estimate is caught", {
  bad <- scen
  bad$lef_mode[1] <- bad$lef_max[1] * 2
  expect_error(validate_inputs(bad), "lef_min <= lef_mode <= lef_max")
})

test_that("a reduction above 100% is caught", {
  bad <- ctl
  bad$sev_red_max[1] <- 1.2
  expect_error(validate_inputs(scen, bad), "between 0 and 1")
})

test_that("a tolerance curve must fall as the loss rises", {
  bad <- tol
  bad$max_probability[2] <- 0.9
  expect_error(validate_inputs(scen, tolerance = bad), "max_probability decrease")
})

test_that("optional columns are checked when present", {
  expect_error(validate_inputs(transform(scen, lef_dist = "beta")), "lef_dist")
  expect_error(validate_inputs(transform(scen, loss_cap = 1)), "loss_cap")
  expect_true(validate_inputs(transform(scen, lef_dist = "pert", loss_cap = NA)))
})
