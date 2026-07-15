# Strict Excel project example

This directory contains synthetic data and equivalent strict plans for two entry styles:

- `DCC-cleaning-plan.xlsx` for survey staff
- `DCC-cleaning-plan.json` for statistical programmers and AI agents

From this directory run:

```r
library(DCC)
dcc_check("responses.csv", "DCC-cleaning-plan.xlsx", "dcc-check")
dcc_run("responses.csv", plan = "DCC-cleaning-plan.xlsx",
        output_dir = "dcc-preview")
```

After reviewing the diagnostics and preview use a new output directory and `mode = "execute"`. All data in this example are synthetic.

