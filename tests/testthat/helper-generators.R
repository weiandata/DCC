acceptance_ruleset <- function() {
  path <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: RANGE_SCORE",
    "    type: range",
    "    variable: score",
    "    min: 0",
    "    max: 100",
    "    severity: warn"
  ), path)
  dcc_rules(path)
}

generated_survey <- function(seed) {
  set.seed(seed)
  n <- sample(c(1L, 2L, 5L, 10L, 20L), 1L)
  pool <- c(NA_real_, -1e300, -1, 0, 25, 50, 100, 101, 1e300)
  data <- data.frame(
    sid = sprintf("S%03d", seq_len(n)),
    score = sample(pool, n, replace = TRUE),
    group = sample(c("A", "B", "\u5317\u4eac", "M\u00fcnchen"),
                   n, replace = TRUE),
    multiselect = sample(c("A|B", "B", "", NA_character_),
                         n, replace = TRUE),
    stringsAsFactors = FALSE
  )
  rules <- acceptance_ruleset()
  list(
    seed = seed,
    data = data,
    rules = rules,
    config = dcc_config(
      rules, actions = list(RANGE_SCORE = "set_na"), id_var = "sid"
    )
  )
}

generated_edge_cases <- function() {
  duplicate <- data.frame(
    sid = c("S1", "S2"), score = c(1, 2), other = c(3, 4),
    check.names = FALSE
  )
  names(duplicate)[3L] <- "score"
  labelled <- haven::labelled(
    c(1, haven::tagged_na("a"), 2),
    labels = c(No = 1, Yes = 2)
  )
  list(
    empty = data.frame(sid = character(), score = numeric()),
    all_missing = data.frame(sid = c("S1", "S2"), score = c(NA, NA)),
    labelled_missing = data.frame(
      sid = c("S1", "S2", "S3"), response = labelled
    ),
    duplicate_names = duplicate,
    extreme = data.frame(
      sid = c("S1", "S2", "S3"), score = c(-1e300, 0, 1e300)
    ),
    unicode = data.frame(
      sid = c("\u8c03\u67e501", "\u8abf\u67fb02"),
      text = c("\u4e2d\u6587", "Espa\u00f1a")
    ),
    multiselect = data.frame(
      sid = c("S1", "S2"), choices = c("A|B", "B|C")
    ),
    zero_match = data.frame(sid = c("S1", "S2"), score = c(25, 75))
  )
}

expect_seed_equal <- function(object, expected, seed) {
  testthat::expect_equal(object, expected, info = paste("generated seed", seed))
}
