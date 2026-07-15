test_that("CSV and TSV adapters preserve identifiers as text", {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,q1", "001,1", "002,"), csv)
  csv_raw <- dcc_get_adapter("csv")$reader(
    csv, list(encoding = "UTF-8")
  )
  expect_identical(csv_raw$data$sid, c("001", "002"))

  tsv <- tempfile(fileext = ".tsv")
  writeLines(c("sid\tq1", "001\t1", "002\t"), tsv)
  tsv_raw <- dcc_get_adapter("tsv")$reader(
    tsv, list(encoding = "UTF-8")
  )
  expect_identical(tsv_raw$data$sid, c("001", "002"))
})

test_that("declared-delimiter TXT and fixed-width adapters are explicit", {
  txt <- tempfile(fileext = ".txt")
  writeLines(c("sid|q1", "001|1"), txt)
  raw <- dcc_get_adapter("txt")$reader(
    txt, list(encoding = "UTF-8", delimiter = "|")
  )
  expect_identical(raw$data$sid, "001")
  expect_error(
    dcc_get_adapter("txt")$reader(txt, list(encoding = "UTF-8")),
    "delimiter", class = "dcc_import_error"
  )

  fwf <- tempfile(fileext = ".txt")
  writeLines(c("00123", "00207"), fwf)
  fixed <- dcc_get_adapter("fwf")$reader(
    fwf,
    list(encoding = "UTF-8", widths = c(3L, 2L),
         col_names = c("sid", "age"))
  )
  expect_identical(fixed$data$sid, c("001", "002"))
  expect_identical(fixed$data$age, c("23", "07"))
})

test_that("JSON, JSONL and RDS adapters return rectangular raw data", {
  js <- tempfile(fileext = ".json")
  writeLines('[{"sid":"001","q1":1},{"sid":"002","q1":null}]', js)
  json <- dcc_get_adapter("json")$reader(js, list(encoding = "UTF-8"))
  expect_identical(json$data$sid, c("001", "002"))
  expect_identical(json$data$q1, c("1", NA_character_))

  jl <- tempfile(fileext = ".jsonl")
  writeLines(c('{"sid":"001","q1":"1"}',
               '{"sid":"002","q1":null}'), jl)
  jsonl <- dcc_get_adapter("jsonl")$reader(jl, list(encoding = "UTF-8"))
  expect_identical(jsonl$data$sid, c("001", "002"))
  expect_identical(jsonl$data$q1, c("1", NA_character_))

  rd <- tempfile(fileext = ".rds")
  saveRDS(data.frame(sid = "001", q1 = 1L), rd)
  rds <- dcc_get_adapter("rds")$reader(rd, list())
  expect_s3_class(rds$data, "data.frame")
  expect_identical(rds$data$sid, "001")

  bad <- tempfile(fileext = ".rds")
  saveRDS(list(sid = "001"), bad)
  expect_error(dcc_get_adapter("rds")$reader(bad, list()),
               "data.frame", class = "dcc_import_error")
})

test_that("structured text rejects nested non-rectangular values", {
  f <- tempfile(fileext = ".json")
  writeLines('[{"sid":"001","nested":{"q1":1}}]', f)
  expect_error(
    dcc_get_adapter("json")$reader(f, list(encoding = "UTF-8")),
    "scalar", class = "dcc_import_error"
  )
})
