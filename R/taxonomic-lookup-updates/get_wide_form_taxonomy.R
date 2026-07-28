get_wide_form_taxonomy <- function(df){
  
  classifications_df <- taxa_df |>
    #dplyr::filter(.data$scientific_id %in% scientific_ids) |>
    dplyr::mutate(
      parent_ranks = purrr::map(.data$id, \(id) {
        .get_parent_rank(id, taxa_df)
      }),
      classifications_df = purrr::map(.data$parent_ranks, \(a) {
        tibble::as_tibble(as.list(a))
      })
    ) |>
    dplyr::select("scientific_id", "classifications_df") |>
    tidyr::unnest("classifications_df") |>
    dplyr::select(
      "scientific_id",
      dplyr::any_of(c(
        "Kingdom",
        "Phylum",
        "Subphylum",
        "Class",
        "Subclass",
        "Order",
        "Family",
        "Genus",
        "Species"
      ))
    )
  
  ranks_df <- taxa_df |>
    #dplyr::filter(.data$scientific_id %in% scientific_ids) |>
    dplyr::select("scientific_id", "rank")
  
  classifications_df <- classifications_df |>
    dplyr::left_join(ranks_df, by = "scientific_id") |>
    dplyr::select("scientific_id", "rank", dplyr::everything())
  
  return(classifications_df)
  
}

.get_parent_rank <- function(node_id, df) {
  parent_ranks <- list()
  
  # First lookup: by raw id column (may be numeric or character)
  row <- dplyr::filter(df, .data$id == node_id)
  
  while (nrow(row) > 0) {
    parent_ranks[[row$rank]] <- row$name
    parent_val <- row$parent_id
    if (is.na(parent_val)) {
      break
    }
    # parent_id holds the scientific_id of the parent — navigate by scientific_id
    row <- dplyr::filter(df, .data$scientific_id == parent_val)
  }
  
  parent_ranks
}
