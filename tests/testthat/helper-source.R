# The helpers use repository-relative paths, so source them from the root
local({
  owd <- setwd(file.path("..", ".."))
  on.exit(setwd(owd))
  for (f in c("R/distributions.R", "R/validate.R", "R/model.R", "R/mcmc.R")) source(f)
})
