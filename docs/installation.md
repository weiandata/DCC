# Installing DCC

DCC is one R package. It does not fork the cleaning engine into separate staff,
statistical, or Agent packages. All packages needed by the declared CSV, text,
Excel/ODS, JSON, RDS, SPSS/Stata/SAS/XPT, Parquet, and Feather adapters are in
`Imports`, so a dependency-aware DCC installation installs them together. PDF
is optional and is not a fixed report output.

## Connected installation

When DCC is available from the configured R repository, use one command:

```r
install.packages("DCC", dependencies = TRUE)
```

For an approved source archive while a package repository remains available:

```r
install.packages("DCC_1.2.0.tar.gz", repos = getOption("repos"),
                 type = "source", dependencies = TRUE)
```

Do not install packages from inside a cleaning run. Installation is an
administrator or environment-build action; DCC only diagnoses unavailable
capabilities at runtime.

## Internal offline installation

An internal bundle is built with:

```sh
Rscript tools/build-internal-bundle.R --download --output=/approved/DCC-bundle
```

The builder requires the exact source archive for every package in `renv.lock`.
If any archive is missing it produces an `.incomplete` diagnostic directory and
refuses to label the bundle complete. A complete bundle contains the DCC source
tarball, all dependency source tarballs, a standard source-repository index,
the lockfile, SHA-256 checksums, a license inventory, an install script, and a
verification report. It contains no survey or user data.

After transferring the bundle, verify `SHA256SUMS`, change into its root, and
run:

```sh
Rscript install-DCC.R /approved/R-library
```

The script uses only the bundled repository and installs DCC plus its dependency
closure into the requested library. The committed `renv.lock` records exact
build versions but `renv` is not a DCC runtime dependency.

## Capacity and system prerequisites

Allow at least 3 GiB of temporary disk space for a complete source installation;
Arrow compilation or retained package caches can require more. Binary repository
installations are usually smaller and faster. R 4.1 or newer is required.
Some packages, especially Arrow, may need platform toolchains or system
libraries when a compatible binary is unavailable.

After installation, run:

```r
library(DCC)
dcc_doctor()
dcc_capabilities()
```

`dcc_doctor()` reports missing packages, old backends, and platform limitations.
`dcc_capabilities()` is the authoritative list of Stable or Experimental
formats and features. Installation availability is not the same as a Stable
claim: format stability also requires the Phase E semantic and three-platform
evidence matrix.

## Verification

Maintainers run:

```sh
Rscript tools/verify-dependencies.R
Rscript tools/verify-format-matrix.R --local
```

The dependency verifier rejects undeclared namespace calls, runtime installer
calls, missing format backends in `Imports`, incomplete lockfiles, and locked
version drift. Clean-install CI repeats installation and format smoke tests on
Linux, macOS, and Windows with repository access disabled during the smoke step.

