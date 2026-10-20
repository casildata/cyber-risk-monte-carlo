# Reproduce every table and figure from the repository root:
#   Rscript run_all.R
# Packages: listed in r-packages.txt; missing ones are installed on first run.

source("R/check_packages.R")
source("R/distributions.R")
source("R/report.R")
source("R/validate.R")
source("R/model.R")
source("R/mcmc.R")

dir.create("outputs", showWarnings = FALSE)
dir.create("docs/figures", showWarnings = FALSE, recursive = TRUE)

pipeline <- c(
  "scripts/01_input_analysis.R",
  "scripts/02_simulate_annual_loss.R",
  "scripts/03_control_roi.R",
  "scripts/04_bayesian_frequency.R",
  "scripts/05_risk_tolerance.R",
  "scripts/06_board_brief.R"
)
for (s in pipeline) {
  message("==> ", s)
  source(s, echo = FALSE)
}
report_write("docs/results.md")
message("Results written to docs/results.md")
