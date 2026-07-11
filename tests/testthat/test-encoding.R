test_that("encoding names normalize to canonical set", {
  expect_identical(normalize_encoding("utf-8"), "UTF-8")
  expect_identical(normalize_encoding("ASCII"), "UTF-8")
  expect_identical(normalize_encoding("GB2312"), "GB18030")
  expect_identical(normalize_encoding("GBK"), "GB18030")
  expect_identical(normalize_encoding("GB18030"), "GB18030")
  expect_identical(normalize_encoding("Big5"), "BIG5")
  expect_identical(normalize_encoding("ISO-8859-1"), "latin1")
  expect_identical(normalize_encoding("windows-1252"), "latin1")
})

test_that("dcc_detect_encoding detects UTF-8 and GB18030", {
  utf8 <- tempfile(fileext = ".csv")
  write_fixture_csv(utf8, "UTF-8")
  det <- dcc_detect_encoding(utf8)
  expect_identical(det$encoding, "UTF-8")

  gb <- tempfile(fileext = ".csv")
  write_fixture_csv(gb, "GB18030")
  det_gb <- dcc_detect_encoding(gb)
  expect_identical(det_gb$encoding, "GB18030")
})

test_that("dcc_detect_encoding handles BOM and empty files", {
  bom <- tempfile(fileext = ".csv")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)),
             charToRaw("a,b\n1,2\n")), bom)
  expect_identical(dcc_detect_encoding(bom)$encoding, "UTF-8")

  empty <- tempfile(fileext = ".csv")
  file.create(empty)
  expect_identical(dcc_detect_encoding(empty)$encoding, "UTF-8")
})

test_that("round-trip: same content from all first-class encodings", {
  encodings <- c("UTF-8", "GB18030", "BIG5")
  ref <- NULL
  for (enc in encodings) {
    f <- tempfile(fileext = ".csv")
    write_fixture_csv(f, enc)
    x <- dcc_read(f) # auto-detected
    expect_identical(x$meta$encoding, enc, label = enc)
    df <- as.data.frame(x)
    if (is.null(ref)) ref <- df else expect_identical(df, ref, label = enc)
  }
  # 北京一中 must survive every encoding intact
  expect_identical(ref$school[1], "北京一中")
})

test_that("explicit encoding override is honoured", {
  f <- tempfile(fileext = ".csv")
  write_fixture_csv(f, "GB18030")
  x <- dcc_read(f, encoding = "GBK") # user says GBK -> normalized GB18030
  expect_identical(x$meta$encoding, "GB18030")
  expect_identical(as.data.frame(x)$school[2], "上海实验")
})
