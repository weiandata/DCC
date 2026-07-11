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

test_that("round-trip: content survives every first-class encoding", {
  # Simplified fixture for UTF-8/GB18030; traditional for BIG5
  # (simplified hanzi are not representable in BIG5).
  cases <- list(
    list(enc = "UTF-8", df = fixture_df()),
    list(enc = "GB18030", df = fixture_df()),
    list(enc = "BIG5", df = fixture_df_trad())
  )
  for (case in cases) {
    f <- tempfile(fileext = ".csv")
    write_fixture_csv(f, case$enc, df = case$df)
    # Explicit encoding: exercises the conversion path deterministically.
    x <- dcc_read(f, encoding = case$enc)
    expect_identical(x$meta$encoding, case$enc, label = case$enc)
    expect_identical(as.data.frame(x)$school, case$df$school,
                     label = case$enc)
  }
})

test_that("BIG5 is auto-detected on a realistic sample", {
  # Detection needs signal: use a longer traditional-Chinese column.
  df <- fixture_df_trad()
  df$comment <- c(
    "這是一份用於測試字元編碼偵測的繁體中文樣本資料。",
    "問卷資料清洗需要正確處理不同編碼的輸入檔案。",
    "臺北高雄臺中臺南桃園新竹基隆嘉義屏東宜蘭花蓮臺東。"
  )
  f <- tempfile(fileext = ".csv")
  write_fixture_csv(f, "BIG5", df = df)
  det <- dcc_detect_encoding(f)
  expect_identical(det$encoding, "BIG5")
  x <- dcc_read(f)
  expect_identical(as.data.frame(x)$school, df$school)
})

test_that("explicit encoding override is honoured", {
  f <- tempfile(fileext = ".csv")
  write_fixture_csv(f, "GB18030")
  x <- dcc_read(f, encoding = "GBK") # user says GBK -> normalized GB18030
  expect_identical(x$meta$encoding, "GB18030")
  expect_identical(as.data.frame(x)$school[2], "上海实验")
})
