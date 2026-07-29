get_taxonomic_tree <- function(df){
  
  # taxon names are used as node IDs, with scientific IDs as an attribute.
  # Therefore there cannot be any duplicate taxon names
  taxa_dupe_names <- df %>%
    count(name) %>%
    filter(n > 1) %>%
    pull(name)
  
  taxa <- df %>%
    mutate(name = case_when(
      name %in% taxa_dupe_names ~ paste0(name, "-", rank, "-", id),
      T ~ name
    ))
  
  # Build a lookup to map parent scientific_id -> parent name
  parent_names <- taxa %>%
    select(scientific_id, name) %>%
    rename(parent_id = scientific_id,
           parent_name = name)
  
  # Use name as node identifier, scientific_id as attribute
  taxa_network <- taxa %>%
    left_join(parent_names, by = c("parent_id")) %>%
    mutate(parent_name = replace_na(parent_name, "top node")) %>%
    rename(child_name = name) %>%
    select(parent_name, child_name, scientific_id, rank)
  
  taxa_tree <- FromDataFrameNetwork(taxa_network, check = "no-warn")
  
  return(taxa_tree)
}

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
