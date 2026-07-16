report_result_fixture <- function(secret = "value 150 outside range") {
  data <- dcc_data(data.frame(
    sid = c("S001", "S002", "S003"),
    score = c(90, 150, 70),
    stringsAsFactors = FALSE
  ))
  findings <- bind_findings(list(
    dcc_findings(
      "S002", variable = "score", check_id = "R001",
      evidence = secret, severity = "fail", dimension = "validity",
      run_id = "reportfixture"
    ),
    dcc_findings(
      "S003", variable = NA_character_, check_id = "R002",
      evidence = "record failed review", severity = "warn",
      dimension = "accuracy", run_id = "reportfixture"
    )
  ))
  dcc_execute(
    data, findings,
    actions = list(R001 = "set_na", R002 = "exclude"),
    id_var = "sid"
  )
}

report_run_fixture <- function(result = report_result_fixture()) {
  structure(
    list(
      mode = "execute",
      config = NULL,
      id_var = "sid",
      files = character(),
      result = result,
      run_id = "reportfixture",
      run_dir = NA_character_,
      status = "success",
      plan = NULL
    ),
    class = "dcc_run"
  )
}

report_model_fixture <- function(secret = "value 150 outside range") {
  result <- report_result_fixture(secret)
  dcc_report_model(result, report_run_fixture(result))
}

plan_with_reports <- function(data, staff = TRUE, statistical = TRUE,
                              machine = TRUE) {
  plan <- plan_fixture(data)
  plan$outputs <- data.frame(
    key = c(
      "report_language", "cleaned_format", "include_staff_report",
      "include_statistical_report", "include_machine_report",
      "statistical_table_format", "include_sensitive_examples"
    ),
    value = c(
      "zh-CN", "csv", staff, statistical, machine, "csv", "FALSE"
    ),
    stringsAsFactors = FALSE
  )
  plan
}
