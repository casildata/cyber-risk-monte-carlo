# Changelog: from the 2022 original to this release

## Rebuild for publication (2026)

**Reframed** the original 2022 simulation engine around cyber risk. The original problem scenarios came from the graduate program and are not redistributed; the techniques carry over:

| Technique from the study | Where it lives now |
|---|---|
| Monte Carlo with triangular / uniform / normal inputs, quantile intervals | `02_simulate_annual_loss.R` (frequency and severity uncertainty, P95/P99) |
| P(outcome < 0) for the NPV model | P(annual loss > threshold) and "years a control pays back" |
| Bootstrap of the newsvendor profit mean | Bootstrap CI for loss avoided in `03_control_roi.R` |
| `fitdistrplus` fits + χ² goodness of fit for the wind-turbine data | `01_input_analysis.R` with `MASS::fitdistr`, AIC, KS and χ² |
| Metropolis-Hastings for λ^8 e^(−10.01λ) | `04_bayesian_frequency.R`, same target, improved sampler |

**Improvements**
- Strengthened the Metropolis-Hastings sampler: records the chain state every iteration and uses a symmetric log-scale proposal with the Jacobian (posterior mean now matches the exact 0.899).
- Burn-in applied consistently to every summary.
- Bug-isolation table: each bug in the original sampler run on its own over 10 chains. The missing Hastings correction causes almost all of the bias (+0.029); storing only accepted proposals adds −0.006.
- Bootstrap Monte Carlo standard errors for the mean, P95 and P99 of every scenario; README figures rounded to match.
- The control interval is labeled as a Monte Carlo CI, with an explanation that it is not uncertainty about control effectiveness.
- Input validation for `scenarios.csv` and `controls.csv`.
- Script 03 reads the number of simulated years from the saved events instead of `max(year)`, which undercounted when the last simulated years had no events.
- Input analysis notes that the Poisson verdict is a miss: the synthetic history was drawn from a negative binomial.
- Framework mapping (FAIR, NIST CSF 2.0, MITRE ATT&CK, CIS Controls v8.1) in the README.
- Two-level uncertainty for control ROI: 90% bands and P(ROSI < 0), with the event rate and control effectiveness held fixed per draw. EDR's chance of losing money is 14%, and it comes entirely from the uncertain event rate.
- Risk tolerance curve (`tolerance.csv`) checked against the loss exceedance curve before and after the controls, on log-probability scales (`05_risk_tolerance.R`).
- Generated one-page board brief (`docs/board-brief.md`, `07_board_brief.R`).
- Beta-PERT frequency option and per-event loss cap (`lef_dist`, `loss_cap`), with a sensitivity table.
- Model logic moved into `R/model.R` and `R/mcmc.R`, with `testthat` unit tests.
- Validation rejects two controls on one scenario, which would subtract the loss avoided twice (combined controls are not modeled yet).
- Value of information: EVPI per control in script 03 and the board brief (about $4k a year for EDR, 3% of its cost).
- Severity uncertainty in the two-level analysis (optional `loss_uncertainty` column): with every loss interval 1.5 times wider, EDR's P(ROSI < 0) rises from 14% to 19%.
- Double extortion as a sensitivity run: 30% of ransomware events also cause a breach loss, breach frequency unchanged on average; the 1-in-100-year loss rises from $7.58M to $7.79M.
- Several controls per scenario: combined effects compound per event (the one-control rule above is lifted). Duplicate control names are rejected.
- Calibrated inputs (`scenarios_calibrated.csv`, script 06, `docs/calibration.md`): ransomware, BEC and data breach re-sized from Cyentia IRIS 2025, Coalition claims data and FBI IC3 2025 for a $500M critical-infrastructure operator. Expected loss $503k vs. $1.20M, but P(loss > $20M) 0.21% against 0.1% tolerated; under these inputs EDR returns −1% and MFA and DLP −73%. The board brief is now script 07. Calibrated year-by-scenario losses (`annual_loss_calibrated_by_year.csv.gz`) are attached to the v1.1 release.
- `simulate_events()` no longer fails when a scenario has no events at all.
- The MCMC posterior for the insider-misuse rate feeds a re-simulation (1.9 times the expert rate; insider ALE $114k to $219k). Split R-hat over four chains and the MCSE of the posterior mean are reported.
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
- Third-party problem statements and data files from the original program.

## Original work (2022)
- Graduate study in Simulation & Optimization, Texas Tech University: Monte Carlo simulation, input analysis, random-number generation, MCMC
