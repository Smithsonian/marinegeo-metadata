observation_ids <- read_csv("observation-lookup/marinegeo_observation_ids.csv")

df <- get_classifications(unique(observation_ids$scientific_id), taxa)

df %>% count(rank)

get_classifications <- function(scientific_ids, taxonomic_lookup) {

  get_parent_rank <- function(node_id, df) {
    parent_ranks <- list()
    current_id <- node_id

    while (length(current_id) > 0 && !is.na(current_id)) {
      row <- df |> filter(id == current_id)
      if (nrow(row) == 0) break

      parent_ranks[[row$rank]] <- row$name
      current_id <- row$parent_id
    }

    parent_ranks
  }

  classifications_df <- taxonomic_lookup |>
    filter(scientific_id %in% scientific_ids) |>
    mutate(
      parent_ranks = pmap(list(id = id), \(id) get_parent_rank(id, taxonomic_lookup)),
      classifications_df = map(parent_ranks, \(a) as_tibble(as.list(a)))
    ) |>
    select(scientific_id, classifications_df) |>
    unnest(classifications_df) |>
    mutate(Phylum = case_when(
      is.na(Phylum) & !is.na(`Phylum (Division)`) ~ `Phylum (Division)`,
      T ~ Phylum
    )) |>
    # Drop all Tribe, Forma, and super-, sub-, infra-, mega-, giga-, parv-, subter- columns
    select(scientific_id, any_of(c(
      "Kingdom",
      "Phylum",
      "Class",
      "Order",
      "Family",
      "Genus",
      "Species"
    )))

  ranks_df <- taxonomic_lookup |>
    select(scientific_id, rank) |>
    filter(scientific_id %in% scientific_ids)

  out_df <- left_join(classifications_df, ranks_df) |>
    select(scientific_id, rank, everything())

  return(out_df)
}
