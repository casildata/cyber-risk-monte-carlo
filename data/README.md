# Data

## `data/assumptions/` (committed, hand-written inputs)

**Illustrative assumptions for a hypothetical mid-size company.** They are not industry
benchmarks; replace them with your own calibrated estimates.

| File | Columns | Meaning |
|---|---|---|
| `scenarios.csv` | `lef_min`, `lef_mode`, `lef_max` | Loss events per year as a triangular estimate (min / most likely / max) |
| | `loss_p05`, `loss_p95` | Calibrated 90% interval for the cost of **one** event, converted to a lognormal |
| | `lef_dist` (optional) | `triangular` (default) or `pert` for the events-per-year estimate |
| | `loss_cap` (optional) | Ceiling on any single loss; blank = uncapped. Must be above `loss_p95` |
| | `loss_uncertainty` (optional) | How uncertain the loss interval itself is, for the ROSI bands in script 03: 1.5 means the typical loss could plausibly be 1.5 times smaller or larger. Blank or 1 = treated as known |
| `controls.csv` | `freq_red_*` | Share of events the control prevents (triangular) |
| | `sev_red_*` | Share of the remaining loss it removes (triangular) |
| | `annual_cost` | Fully loaded yearly cost of the control |
| | (several rows per scenario) | Allowed. Combined, a second control acts on what the first leaves: losses are multiplied by (1 − r<sub>1</sub>)(1 − r<sub>2</sub>), not reduced twice |
| `scenarios_calibrated.csv` | same columns as `scenarios.csv`, plus `confidence` and `source` | The scenarios re-sized from public sources for a mid-size US critical-infrastructure operator; see [`docs/calibration.md`](../docs/calibration.md). Used only by script 06 |
| `tolerance.csv` | `loss`, `max_probability` | The risk appetite as points on a curve: the most acceptable chance that annual loss exceeds `loss`. Loss rises and probability falls down the rows |

All three files are checked before the simulation runs (`R/validate.R`); a bad row stops the run with a message naming it.

## `data/generated/` (git-ignored, written by `scripts/01_input_analysis.R`)

Synthetic stand-ins for internal records, seeded for reproducibility:
- `monthly_incidents.csv`: 48 months of incident counts (negative binomial, mean 1.2)
- `bec_loss_history.csv`: 60 past business-email-compromise losses drawn from the BEC scenario's lognormal

To use real history, replace these two files (same columns) and comment out the
generation block at the top of script 01.
