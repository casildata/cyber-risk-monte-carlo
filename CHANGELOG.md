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
- Repository-relative paths; dependencies reduced to base R, MASS, ggplot2, scales and patchwork.
- Added `run_all.R`, a generated results report and figures.

**Not included**
- Course-provided problems and data files.

## Original submission (Spring 2022)
- ISQS 7339 Homework 2: Monte Carlo simulation, input analysis, random-number generation, MCMC
