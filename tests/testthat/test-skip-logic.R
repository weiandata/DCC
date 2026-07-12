rules_from <- function(lines) {
  rf <- tempfile(fileext = ".yaml")
  writeLines(lines, rf)
  dcc_rules(rf)
}

skip_data <- function() {
  data.frame(
    sid = c("S1", "S2"),
    q1 = c(2, 1),        # S1 triggers the skip (q1 == 2); S2 does not
    q2 = c(NA, 5),
    q3 = c(NA, 4),
    q4 = c(NA, NA),      # S2 genuinely omits q4
    stringsAsFactors = FALSE
  )
}

test_that("without skip_logic a full skip counts as missingness", {
  skip_if_not_installed("yaml")
  rules <- rules_from(c(
    "checks:",
    "  - id: M1",
    "    type: missing_items",
    "    items: [q2, q3, q4]",
    "    max_prop: 0.3"
  ))
  f <- dcc_detect(skip_data(), rules, id_var = "sid")
  expect_true("S1" %in% f$record_id)   # S1: 100% of q2..q4 missing
})

test_that("skip_logic marks skipped items as not administered", {
  skip_if_not_installed("yaml")
  rules <- rules_from(c(
    "checks:",
    "  - id: SK",
    "    type: skip_logic",
    "    when:",
    "      variable: q1",
    "      equals: 2",
    "    then_not_required: [q2, q3, q4]",
    "  - id: M1",
    "    type: missing_items",
    "    items: [q2, q3, q4]",
    "    max_prop: 0.3"
  ))
  f <- dcc_detect(skip_data(), rules, id_var = "sid")
  # S1 legitimately skipped q2..q4 -> not flagged
  expect_false("S1" %in% f$record_id)
  # S2 answered q2,q3 and omitted q4 (1/3 = 33% > 30%) -> still flagged
  expect_true("S2" %in% f$record_id)
})

test_that("skip_logic is rejected in chunked mode", {
  skip_if_not_installed("yaml")
  rules <- rules_from(c(
    "checks:",
    "  - id: SK",
    "    type: skip_logic",
    "    when:",
    "      variable: q1",
    "      equals: 2",
    "    then_not_required: [q2]"
  ))
  csv <- tempfile(fileext = ".csv")
  data.table::fwrite(skip_data(), csv)
  expect_error(dcc_detect_chunked(csv, rules, id_var = "sid"),
               class = "dcc_chunk_error")
})
