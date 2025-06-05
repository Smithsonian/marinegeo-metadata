# Not using this function because I do not yet want to update the taxonomic file unsupervised

db_add_new_taxonomic_ids <- function(df,
                                     taxonomic_id_column = "taxonomic_id",
                                     identification_column_name = "scientific_name"){

  # Test inputs
  stopifnot("`df` must be a dataframe" = is.data.frame(df))
  stopifnot("`identification_column_name` must be a character" = is.character(identification_column_name))

  # Check for necessary columns to process dataframe
  missing_columns <- dplyr::setdiff(c(identification_column_name, taxonomic_id_column), colnames(df))

  if (length(missing_columns) > 0) {
    stop(paste("Missing required column(s):", paste(missing_columns, collapse = ", ")))
  }

  # If necessary, rename columns to allow join with taxonomic database
  if(identification_column_name != "scientific_name"){

    df <- df |>
      dplyr::rename(scientific_name := dplyr::all_of(identification_column_name))

  }

  if(taxonomic_id_column != "taxonomic_id"){

    df <- df |>
      dplyr::rename(taxonomic_id := dplyr::all_of(taxonomic_id_column))

  }




}
