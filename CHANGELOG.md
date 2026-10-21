# Changelog: coursework → public repository

## Rebuild for publication (2026)

**Reframed** the ISQS 7339 Homework 2 simulation engine around cyber risk. The
homework scenarios were course-provided and are not included; the techniques carry over:

| Homework technique | Where it lives now |
|---|---|
| Monte Carlo with triangular / uniform / normal inputs, quantile intervals | `02_simulate_annual_loss.R` (frequency and severity uncertainty, P95/P99) |
| P(outcome < 0) for the NPV model | P(annual loss > threshold) and "years a control pays back" |
| Bootstrap of the newsvendor profit mean | Bootstrap CI for loss avoided in `03_control_roi.R` |
| `fitdistrplus` fits + χ² goodness of fit for the wind-turbine data | `01_input_analysis.R` with `MASS::fitdistr`, AIC, KS and χ² |
| Metropolis-Hastings for λ^8 e^(−10.01λ) | `04_bayesian_frequency.R`, same target, improved sampler |

**Improvements**
- Strengthened the Metropolis-Hastings sampler: records the chain state every iteration and uses a symmetric log-scale proposal with the Jacobian (posterior mean now matches the exact 0.899).
- Burn-in applied consistently to every summary.
- Bug-isolation table: each coursework sampler bug run on its own over 10 chains. The missing Hastings correction causes almost all of the bias (+0.029); storing only accepted proposals adds −0.006.
- Bootstrap Monte Carlo standard errors for the mean, P95 and P99 of every scenario; README figures rounded to match.
- The control interval is labeled as a Monte Carlo CI, with an explanation that it is not uncertainty about control effectiveness.
- Input validation for `scenarios.csv` and `controls.csv`.
- Script 03 reads the number of simulated years from the saved events instead of `max(year)`, which undercounted when the last simulated years had no events.
- Input analysis notes that the Poisson verdict is a miss: the synthetic history was drawn from a negative binomial.
- Framework mapping (FAIR, NIST CSF 2.0, MITRE ATT&CK, CIS Controls v8.1) in the README.
- Two-level uncertainty for control ROI: 90% bands and P(ROSI < 0), with the event rate and control effectiveness held fixed per draw. EDR's chance of losing money is 14%, and it comes entirely from the uncertain event rate.
- Risk tolerance curve (`tolerance.csv`) checked against the loss exceedance curve before and after the controls, on log-probability scales (`05_risk_tolerance.R`).
- Generated one-page board brief (`docs/board-brief.md`, `06_board_brief.R`).
- Beta-PERT frequency option and per-event loss cap (`lef_dist`, `loss_cap`), with a sensitivity table.
- Model logic moved into `R/model.R` and `R/mcmc.R`, with `testthat` unit tests.
- Validation rejects two controls on one scenario, which would subtract the loss avoided twice (combined controls are not modeled yet).
- Board-brief statements that the event rate drives the chance of losing money now print only when the numbers support them.
- README leads with the log-scale tolerance figure; P(ROSI < 0) shown as "about 14%" for EDR and DLP (the decimal is seed noise); NIST CSF 2.0 outcomes quoted verbatim.
- Minimum R raised to 4.4 (`renv.lock` pins MASS 7.3-65); CI pinned to Ubuntu 24.04.
- Missing packages stop the run with install instructions instead of installing automatically.
- The MCMC example is now framed as insider-misuse incidents, a scenario the model includes.
- GitHub Actions: unit tests, full pipeline, a check that every reported number is reproduced, and a gitleaks secret scan; `renv.lock` pins package versions.
- Year-by-scenario annual losses exported (`annual_loss_by_year.csv.gz`) and attached to the v1.0 release.
- The loss-avoided figure states how many years with $0 avoided it leaves out.
- Repository-relative paths; dependencies reduced to base R, MASS, ggplot2, scales and patchwork.
- Added `run_all.R`, a generated results report and figures.

**Not included**
- Course-provided problems and data files.

## Original submission (Spring 2022)
- ISQS 7339 Homework 2: Monte Carlo simulation, input analysis, random-number generation, MCMC
