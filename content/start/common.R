knitr::opts_chunk$set(
  digits = 3,
  comment = "#>",
  dev = 'svglite', 
  dev.args = list(bg = "transparent"),
  fig.path = "figs/",
  collapse = TRUE,
  cache.path = "cache/"
)
options(width = 80, cli.width = 70)

req_pkgs <- function(x, what = "이 장에 있는 코드를 사용하려면, ") {
  x <- sort(x)
  x <- knitr::combine_words(x, and = " and ")
  paste0(
    what,
    " 다음 패키지들을 인스톨해야 합니다: ",
    x, "." 
  )
}
small_session <- function(pkgs = NULL) {
  pkgs <- c(pkgs, "recipes", "parsnip", "tune", "workflows", "dials", "dplyr",
            "broom", "ggplot2", "purrr", "rlang", "rsample", "tibble", "infer",
            "yardstick", "tidymodels", "infer")
  pkgs <- unique(pkgs)
  library(sessioninfo)
  library(dplyr)
  sinfo <- sessioninfo::session_info()
  cls <- class(sinfo$packages)
  sinfo$packages <- 
    sinfo$packages %>% 
    dplyr::filter(package %in% pkgs)
  class(sinfo$packages) <- cls
  sinfo
}
