canonical_contract_fixture <- function() {
  source <- tempfile(fileext = ".csv")
  writeLines(c("sid,q1", "S1,1", "S2,"), source)
  columns <- data.frame(
    source_name = c("sid", "q1"),
    name = c("sid", "q1"),
    type = c("character", "integer"),
    stringsAsFactors = FALSE
  )
  list(
    source = source,
    spec = new_import_spec(source, "csv", columns = columns),
    dictionary = data.table::data.table(
      name = c("sid", "q1"),
      source_name = c("sid", "q1"),
      type = c("character", "integer"),
      role = c("id", "item")
    ),
    missing = data.table::data.table(
      row = 2L,
      variable = "q1",
      state = "respondent_omission",
      source_value = NA_character_
    )
  )
}

test_that("canonical data preserves dictionary and missing semantics", {
  fx <- canonical_contract_fixture()
  d <- data.table::data.table(sid = c("S1", "S2"), q1 = c(1L, NA_integer_))
  x <- dcc_data(d, dictionary = fx$dictionary,
                missing_states = fx$missing, import_spec = fx$spec)
  expect_identical(dcc_dictionary(x), fx$dictionary)
  expect_identical(dcc_missing_states(x)$state, "respondent_omission")
  expect_identical(x$import_spec, fx$spec)

  returned <- dcc_dictionary(x)
  returned$name[1L] <- "changed"
  expect_identical(dcc_dictionary(x)$name[1L], "sid")
})

test_that("canonical metadata contracts reject ambiguous values", {
  fx <- canonical_contract_fixture()
  duplicate <- fx$dictionary[c(1L, 1L)]
  expect_error(
    dcc_data(data.frame(sid = "S1"), dictionary = duplicate),
    class = "dcc_import_error"
  )
  invalid_missing <- data.table::copy(fx$missing)
  invalid_missing$state <- "mystery"
  expect_error(
    dcc_data(data.frame(sid = "S1", q1 = NA),
             missing_states = invalid_missing),
    class = "dcc_import_error"
  )
  expect_error(
    new_import_spec(fx$source, "csv", options = "guess",
                    columns = data.frame(source_name = "sid", name = "sid")),
    class = "dcc_import_error"
  )
})

test_that("canonical metadata survives execution and scoring", {
  fx <- canonical_contract_fixture()
  x <- dcc_data(
    data.frame(sid = c("S1", "S2"), q1 = c(1L, NA_integer_)),
    dictionary = fx$dictionary,
    missing_states = fx$missing,
    import_spec = fx$spec
  )
  findings <- dcc_findings("S1", variable = "q1", check_id = "KEEP",
                           evidence = "reviewed")
  executed <- dcc_cleaned(dcc_execute(
    x, findings, actions = list(KEEP = "flag"), id_var = "sid"
  ))
  expect_identical(dcc_dictionary(executed), fx$dictionary)
  expect_identical(dcc_missing_states(executed), fx$missing)
  expect_identical(executed$import_spec, fx$spec)

  scored <- dcc_score(
    x,
    data.frame(item = "q1", key = "1", stringsAsFactors = FALSE)
  )
  expect_identical(dcc_dictionary(scored), fx$dictionary)
  expect_identical(dcc_missing_states(scored), fx$missing)
  expect_identical(scored$import_spec, fx$spec)
})

test_that("canonical metadata accessors reject non-dcc data", {
  expect_error(dcc_dictionary(data.frame()), class = "dcc_type_error")
  expect_error(dcc_missing_states(data.frame()), class = "dcc_type_error")
})

test_that("legacy dcc_data objects expose empty canonical metadata", {
  legacy <- structure(
    list(data = data.table::data.table(sid = "S1"), meta = list(),
         read_report = NULL, provenance = list()),
    class = "dcc_data"
  )
  expect_identical(dcc_dictionary(legacy), empty_dictionary())
  expect_identical(dcc_missing_states(legacy), empty_missing_states())
})
