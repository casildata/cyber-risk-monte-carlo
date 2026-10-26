# Calibrating the inputs

[`data/assumptions/scenarios_calibrated.csv`](../data/assumptions/scenarios_calibrated.csv) replaces the illustrative frequencies and loss ranges with estimates sized from public sources for one profile: a **mid-size US critical-infrastructure operator** (utility, energy or transport-adjacent, about $500M revenue and 2,000 employees). Section 6 of [`results.md`](results.md) runs the same model on both files.

This is a calibration, not a measurement. Every source counts something slightly different from what the model needs (insurance claims above a retention, publicly reported incidents, complaints to the FBI), so each row says where its numbers came from and how much to trust them. Where sources disagree, the disagreement becomes the min–max range rather than being averaged away.

## Sources

| Short name | Source | What it gives |
|---|---|---|
| IRIS 2025 | Cyentia Institute, [*Information Risk Insights Study 2025: It's About Time*](https://www.cyentia.com/publication/iris2025/) | Annual probability of a significant (publicly reported) incident by sector and revenue tier; loss distributions by revenue tier and by incident pattern. Losses in 2024 dollars |
| Coalition 2025 | Coalition, [*2025 Cyber Claims Report*](https://www.coalitioninc.com/blog/cyber-insurance/2025-cyber-claims-report) (2024 claims) | Claims frequency and severity by revenue band and event type, from cyber insurance policyholders |
| Coalition 2026 | Coalition, [*2026 Cyber Claims Report* announcement](https://www.coalitioninc.com/announcements/2026-cyber-claims-report) (2025 claims) | Cross-checks: funds-transfer-fraud and ransomware severity, share of ransomware with data theft |
| IC3 2025 | FBI Internet Crime Complaint Center, [*2025 IC3 Annual Report*](https://www.ic3.gov/AnnualReport/Reports/2025_IC3Report.pdf) | Business email compromise complaints and reported losses |
| AFP 2025 | Association for Financial Professionals, [2025 Payments Fraud and Control Survey](https://www.financialprofessionals.org/about/learn-more/press-releases/Details/survey-79-percent-of-organizations-were-victims-of-attempted-or-actual-payments-fraud-activity-in-2024) (521 corporate practitioners, January 2025); the BEC loss share as reported by [Digital Transactions](https://www.digitaltransactions.net/business-email-compromise-remains-the-no-1-fraud-attempt-avenue/) | Share of organizations targeted by BEC (63%) and with a BEC loss (36%) in 2024 |
| Sophos 2026 | Sophos, [*The State of Ransomware*](https://www.sophos.com/en-us/content/state-of-ransomware) (2,158 organizations, 100–5,000 employees) | Cross-check: average recovery cost $1.7M, median ransom payment $769K |
| IBM 2025 | IBM, [Cost of a Data Breach 2025](https://newsroom.ibm.com/2025-07-30-ibm-report-13-of-organizations-reported-breaches-of-ai-models-or-applications,-97-of-which-reported-lacking-proper-ai-access-controls) | Cross-check: US average breach cost $10.22M |

## Size adjustment for loss magnitude

IRIS gives per-pattern losses for all firm sizes together, and overall losses per revenue tier. The ratio between the two gives a size adjustment for the $100M–$1B tier:

| IRIS 2025 | Median | 95th percentile |
|---|---|---|
| All firms, 2015–2024 (Figure 9) | $603K | $32M |
| $100M to $1B (Table 1) | $466.7K | $12.3M |

Treating losses as lognormal, the tier's median is **0.774×** the all-firm median, and its log-scale spread is **0.824×**:

```
median factor = 466.7K / 603K = 0.774
spread factor = ln(12.3M / 466.7K) / ln(32M / 603K) = 3.272 / 3.971 = 0.824
```

A pattern's all-size 2024 median *m* and 90th percentile *p90* (IRIS Figure 15) become a tier distribution with median 0.774 *m* and log-sd 0.824 · ln(*p90*/*m*) / 1.2816; its 5th and 95th percentiles are the `loss_p05` and `loss_p95` the model reads.

## Frequency

The model needs events per year. A probability *p* of at least one event in a year converts to a Poisson rate λ = −ln(1 − *p*).

## Scenario by scenario

### Ransomware (confidence: medium)

| Input | Value | Derivation |
|---|---|---|
| `lef_min` | 0.003 | Coalition 2025: ransomware claims frequency 0.31% across all policyholders |
| `lef_mode` | 0.013 | Coalition 2025: claims frequency 5.97% for $100M+ revenue × ransomware 21.1% of claims → *p* = 1.26%, λ = 0.0127 |
| `lef_max` | 0.077 | IRIS 2025: 9.3% chance of any significant incident × 0.80 for the $100M–$1B tier → *p* = 7.44%, λ = 0.077. A ceiling: every incident a ransomware event |
| `loss_p05`, `loss_p95` | $250K, $24M | IRIS 2025 ransomware, 2024: median $3.2M, 90th percentile $27.6M → tier median $2.48M, log-sd 1.385 → mean per event $6.5M |

Cross-checks: Sophos 2026 puts the average recovery cost at $1.7M before any ransom (median payment $769K), and Coalition 2025 the average insured ransomware claim at $292K. Both sit inside the interval; the IRIS-based mean is higher because publicly reported incidents skew large, and insured claims stop at policy limits. 70% of Coalition's 2025 ransomware claims involved data theft as well as encryption (Coalition 2026); IRIS's ransomware losses already include those cases, so the calibrated run does not add the double-extortion mechanism on top.

### Business email compromise (confidence: low)

The scenario is a fraudulent wire transfer after a mailbox takeover, which insurers file as funds transfer fraud.

| Input | Value | Derivation |
|---|---|---|
| `lef_min` | 0.018 | Coalition 2025: 5.97% × funds transfer fraud 29.8% of claims → λ = 0.018. Insured claims miss losses below the retention, so this is a floor |
| `lef_max` | 0.45 | AFP 2025: 36% of organizations had a BEC loss in 2024 → λ = 0.446. Respondents are treasury practitioners, so this leans high |
| `lef_mode` | 0.090 | Geometric mean of the two, since they differ by 25× |
| `loss_p05`, `loss_p95` | $10K, $410K | IC3 2025: $3,046,598,558 over 24,768 BEC complaints = $123K mean per complaint. The illustrative 40× spread is kept and centered on that mean |

Cross-check: Coalition puts the average funds-transfer-fraud claim at $106K (2024) and $141K (2025).

### Customer data breach (confidence: low)

| Input | Value | Derivation |
|---|---|---|
| `lef_min`, `lef_mode`, `lef_max` | 0.010, 0.025, 0.060 | IRIS 2025 brackets the rate of *any* significant incident for this profile: 4.5% for utilities (λ = 0.046) to 7.4% for the revenue tier (λ = 0.077). Intrusion with data theft is taken as roughly a fifth to three quarters of that, with the mode near half of the utilities rate. Analyst judgment within a sourced envelope |
| `loss_p05`, `loss_p95` | $160K, $6.3M | IRIS 2025 system intrusion, 2024: median $1.3M, 90th percentile $7.4M → tier median $1.01M, log-sd 1.118 → mean per event $1.9M |

Cross-check: IBM's US average of $10.22M is far above this interval's mean. It is an average over breached organizations of every size, and a mean is pulled up by the largest breaches, while the IRIS figures are size-adjusted medians and percentiles; treat the calibrated breach losses as the typical case for this profile, not the worst.

### DDoS outage and insider misuse (not calibrated)

No public source gives per-incident losses for DDoS at this size, and IRIS's insider and accidental-disclosure losses (2024 median $6.9K, 90th percentile $1.6M) mix trivial and severe cases in a way one lognormal cannot represent. Both rows keep their illustrative values, so in the calibrated run they carry about half of the expected loss (see section 6).

## What is still illustrative

- Control costs and effectiveness ranges (`controls.csv`).
- The risk tolerance curve (`tolerance.csv`).
- The company profile itself: a different revenue tier or sector changes every row above.
