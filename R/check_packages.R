# Stop with install instructions if any CRAN package listed in r-packages.txt
# is missing. Nothing is installed automatically: renv::restore() installs the
# exact versions the results were produced with. Run from the repository root.

check_packages <- function(file = "r-packages.txt") {
  pkgs <- trimws(sub("#.*", "", readLines(file, warn = FALSE)))
  pkgs <- pkgs[nzchar(pkgs)]
  installed <- function(p) nzchar(system.file(package = p))
  missing <- pkgs[!vapply(pkgs, installed, logical(1))]
  if (length(missing) == 0) return(invisible(TRUE))

  stop("Missing R packages: ", paste(missing, collapse = ", "), "\n",
       "Install the tested versions from renv.lock (recommended):\n",
       "  install.packages(\"renv\"); renv::restore()\n",
       "or the current CRAN versions:\n",
       sprintf("  install.packages(c(%s))", paste0('"', missing, '"', collapse = ", ")),
       call. = FALSE)
}

check_packages()
