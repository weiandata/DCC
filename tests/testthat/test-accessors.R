test_that("dcc_unhandled returns the unhandled findings set", {
  df <- fixture_responses()
  f <- dcc_findings("S001", variable = "q1", check_id = "C", evidence = "e")
  res <- dcc_execute(df, f, actions = list(), id_var = "sid")
  expect_identical(dcc_unhandled(res)$finding_id, res$unhandled$finding_id)
  expect_s3_class(dcc_unhandled(res), "dcc_findings")
  expect_error(dcc_unhandled(df), class = "dcc_type_error")
})

test_that("dcc_item_map and dcc_mapping_findings expose the map attributes", {
  data <- data.frame(sid = c("S1", "S2"), form = c("A", "B"),
                     p1 = c(1, 2), p2 = c(5, 6))
  fmap <- data.frame(form = c("A", "A", "B", "B"),
                     source = c("p1", "p2", "p1", "p2"),
                     master = c("M001", "M002", "M003", "M002"),
                     is_anchor = c(FALSE, TRUE, FALSE, TRUE))
  mapped <- dcc_map_forms(data, fmap, form_var = "form")
  expect_identical(dcc_item_map(mapped),
                   attr(mapped, "dcc_item_map", exact = TRUE))
  expect_identical(dcc_mapping_findings(mapped),
                   attr(mapped, "dcc_findings", exact = TRUE))
  # wrong object: no map attribute
  expect_error(dcc_item_map(data.frame(a = 1)), class = "dcc_type_error")
  expect_error(dcc_mapping_findings(data.frame(a = 1)),
               class = "dcc_type_error")
})
