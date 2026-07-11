#' Detect the character encoding of a text file
#'
#' Reads up to `n_bytes` from the file and detects the most likely
#' character encoding via [stringi::stri_enc_detect()]. Detected encodings
#' are normalized to the canonical names DCC supports as first-class:
#' `"UTF-8"`, `"GB18030"` (covers GBK/GB2312), `"BIG5"`, and `"latin1"`
#' (covers ISO-8859-1 / windows-1252).
#'
#' @param path Path to the file.
#' @param n_bytes Maximum number of bytes to sample (default 65536).
#' @return A list with elements `encoding` (normalized name), `confidence`
#'   (0-1), and `candidates` (data.frame of raw detector output).
#' @export
dcc_detect_encoding <- function(path, n_bytes = 65536L) {
  if (!file.exists(path)) {
    dcc_abort("File not found: ", path, class = "dcc_io_error")
  }
  raw <- readBin(path, what = "raw",
                 n = min(n_bytes, file.size(path)))
  if (length(raw) == 0L) {
    return(list(encoding = "UTF-8", confidence = NA_real_,
                candidates = data.frame()))
  }

  # BOM short-circuit
  if (length(raw) >= 3L &&
      identical(raw[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) {
    return(list(encoding = "UTF-8", confidence = 1,
                candidates = data.frame(Encoding = "UTF-8-BOM",
                                        Confidence = 1)))
  }

  det <- stringi::stri_enc_detect(raw)[[1]]
  if (nrow(det) == 0L) {
    dcc_abort("Could not detect encoding of ", path,
              "; pass `encoding` explicitly.", class = "dcc_encoding_error")
  }
  list(
    encoding = normalize_encoding(det$Encoding[1]),
    confidence = det$Confidence[1],
    candidates = det
  )
}

normalize_encoding <- function(enc) {
  enc_up <- toupper(gsub("[ _]", "-", enc))
  if (enc_up %in% c("UTF-8", "ASCII", "US-ASCII", "UTF8")) {
    return("UTF-8")
  }
  if (grepl("^GB", enc_up) || enc_up %in% c("HZ-GB-2312", "EUC-CN")) {
    return("GB18030")
  }
  if (grepl("^BIG-?5", enc_up)) {
    return("BIG5")
  }
  if (enc_up %in% c("ISO-8859-1", "LATIN1", "LATIN-1", "WINDOWS-1252",
                    "CP1252")) {
    return("latin1")
  }
  # Pass through anything else (e.g. UTF-16); reader will attempt iconv.
  enc
}

#' Read a text file as UTF-8, converting from a source encoding
#'
#' @param path File path.
#' @param encoding Source encoding (normalized name).
#' @return A length-1 UTF-8 character vector of the file contents.
#' @keywords internal
#' @noRd
read_file_utf8 <- function(path, encoding) {
  raw <- stringi::stri_read_raw(path)
  if (identical(encoding, "UTF-8")) {
    txt <- stringi::stri_conv(raw, from = "UTF-8", to = "UTF-8")
  } else {
    txt <- stringi::stri_conv(raw, from = encoding, to = "UTF-8")
  }
  # Strip BOM if present
  sub("^﻿", "", txt)
}
