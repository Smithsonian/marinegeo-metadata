# Table Metadata

Table metadata are found in `\table-metadata`. There are two sub-directories, each containing a type of metadata. Each CSV file within a sub-directory shares the same column structure and data types. The two types of metadata include:

1. `data-structure`: One row per column in a given data table, defining the expected column name and data type. Columns include `protocol` (the monitoring or experiment program), `table_id` (a versioned identifier for the specific data table), `level` (the data processing level), `column_name`, and `data_type`. One CSV per protocol (e.g., seagrass monitoring, oyster reef monitoring).
2. `categorical-values`: One row per valid value for a given categorical column in a given data table. Columns include `table_id`, `column_name`, and `value`. These define the controlled vocabulary for fields where only specific values are permitted. One CSV per protocol.

- The `table_id` column links both tables to each other and to `marinegeo_data_index.csv` (in the repository root), which maps each `table_id` to its protocol, data level, human-readable name, and storage location.
- Data types in `data-structure` use SQL-style type names (e.g., `STRING`, `INT`, `DOUBLE`, `DATE`, `BOOL`, `TINYINT`).
- Not all columns in a table require entries in `categorical-values` — only those with a restricted set of valid values are listed.
