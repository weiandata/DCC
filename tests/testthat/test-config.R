test_that("dcc_read_config round-trips the template workbook", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  dcc_write_config_template(path)

  cfg <- dcc_read_config(path)
  expect_s3_class(cfg, "dcc_config")
  expect_identical(cfg$id_var, "sid")
  expect_identical(cfg$items, c("q1", "q2", "q3"))

  ids <- vapply(cfg$rules$checks, function(ch) ch$id, character(1))
  expect_setequal(ids, c("R001", "M001"))

  # range rule parsed with its bounds and variable
  r001 <- cfg$rules$checks[[which(ids == "R001")]]
  expect_identical(r001$type, "range")
  expect_identical(r001$variable, "score")
  expect_equal(r001$max, 100)

  # detector rule parsed with its items
  m001 <- cfg$rules$checks[[which(ids == "M001")]]
  expect_identical(m001$type, "missing_items")
  expect_identical(m001$items, c("q1", "q2", "q3"))

  # actions are keyed by the declared rule id for every rule type
  expect_identical(cfg$actions$R001, "set_na")
  expect_identical(cfg$actions$M001, "flag")
})

test_that("dcc_read_config config drives a dcc_run", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  skip_if_not_installed("yaml")
  path <- tempfile(fileext = ".xlsx")
  dcc_write_config_template(path)
  cfg <- dcc_read_config(path)

  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score,q1,q2,q3",
               "S1,90,1,2,3",
               "S2,150,4,5,1"), csv)
  out <- tempfile("dcc-out")
  run <- dcc_run(csv, cfg, out, mode = "execute")
  expect_true(file.exists(file.path(out, "cleaned-data.csv")))
})

test_that("a workbook missing required sheets is a typed error", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(other = data.frame(a = 1)), path)
  expect_error(dcc_read_config(path), class = "dcc_config_error")
})
