# Install any CRAN packages listed in r-packages.txt that are missing.
# In an interactive session (RStudio, VS Code R console) it asks first;
# under Rscript it installs them automatically. Run from the repository root.

check_packages <- function(file = "r-packages.txt") {
  pkgs <- trimws(sub("#.*", "", readLines(file, warn = FALSE)))
  pkgs <- pkgs[nzchar(pkgs)]
  installed <- function(p) nzchar(system.file(package = p))
  missing <- pkgs[!vapply(pkgs, installed, logical(1))]
  if (length(missing) == 0) return(invisible(TRUE))

  install_cmd <- sprintf('install.packages(c(%s))',
                         paste0('"', missing, '"', collapse = ", "))
  message("Missing R packages: ", paste(missing, collapse = ", "))
  if (interactive()) {
    answer <- readline("Install them now from CRAN? [Y/n] ")
    if (tolower(substr(trimws(answer), 1, 1)) == "n") {
      stop("Not installed. To install later, run:\n  ", install_cmd, call. = FALSE)
    }
  }

  repos <- getOption("repos")
  if (is.null(repos) || !nzchar(repos[["CRAN"]]) || repos[["CRAN"]] == "@CRAN@") {
    repos <- c(CRAN = "https://cloud.r-project.org")
  }
  # Fall back to the personal library when the default one isn't writable
  # (e.g. R installed under C:/Program Files without admin rights).
  lib <- .libPaths()[1]
  if (file.access(lib, 2) != 0) {
    lib <- Sys.getenv("R_LIBS_USER")
    dir.create(lib, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(lib, .libPaths()))
  }
  install.packages(missing, lib = lib, repos = repos)

  failed <- missing[!vapply(missing, installed, logical(1))]
  if (length(failed) > 0) {
    stop("Could not install: ", paste(failed, collapse = ", "),
         "\nTry manually:\n  ", install_cmd, call. = FALSE)
  }
  invisible(TRUE)
}

check_packages()
