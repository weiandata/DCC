# DCC format fixtures

Format tests generate small workbooks at runtime when the corresponding writer
is deterministic and installed. Legacy XLS coverage uses the readxl package's
installed XLS fixture because DCC does not add a legacy XLS writer dependency.

Every fixture must declare its worksheet and range. A backend opening a file is
not sufficient for Stable status; semantic parity and the Phase E platform
matrix remain required.
