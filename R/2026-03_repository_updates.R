library(tidyverse)

## Observation lookup ####

observation_df <- read_csv("observation-lookup/marinegeo-taxonomic-ids.csv")

species <- observation_df %>%
  filter(taxonomic_id > 0) %>%
  mutate(scientific_id = paste0("APHIA:", taxonomic_id))

functional <- observation_df %>%
  filter(taxonomic_id < 1) %>%
  mutate(scientific_id = paste0(
    "FUNCTIONAL:", abs(taxonomic_id)
  ))

updated_df <- bind_rows(functional, species) %>%
  distinct()

write_csv(updated_df, "observation-lookup/marinegeo_observation_ids.csv")

observation_df <- read_csv("observation-lookup/marinegeo_observation_ids.csv")

updated_df <- observation_df %>%
  select(-taxonomic_id)

write_csv(updated_df, "observation-lookup/marinegeo_observation_ids.csv")

## Taxonomic lookup ####

# Archived!
# taxa_df <- read_csv("taxonomic-lookup/marinegeo_classifications.csv")
#
# taxa_updated <- taxa_df %>%
#   filter(taxonomic_id > 0) %>%
#   mutate(scientific_id = paste0("APHIA:", taxonomic_id)) %>%
#   mutate(taxonomic_id_type = "aphia") %>%
#   rename(rank = level) %>%
#   select(scientific_id, taxonomic_id, taxonomic_id_type, rank, everything()) %>%
#   distinct()
#
# write_csv(taxa_updated, "taxonomic-lookup/marinegeo_taxonomic_classifications.csv")
#
# taxa_updated %>%
#   count(taxonomic_id) %>%
#   filter(n > 1)

taxa_df <- read_csv("taxonomic-lookup/marinegeo_classifications.csv")

ids <- unique(taxa_df$taxonomic_id)

ids1 <- ids[1:100]
ids2 <- ids[101:200]
ids3 <- ids[201:300]
ids4 <- ids[301:400]
ids5 <- ids[401:500]
ids6 <- ids[501:600]
ids7 <- ids[601:700]
ids8 <- ids[701:800]
ids9 <- ids[801:900]
ids10 <- ids[901:1000]
ids11 <- ids[1001:1100]
ids12 <- ids[1101:1200]
ids13 <- ids[1201:1341]

out1 <- classification(ids1, db="worms")
out2 <- classification(ids2, db="worms")
out3 <- classification(ids3, db="worms")
out4 <- classification(ids4, db="worms")
out5 <- classification(ids5, db="worms")
out6 <- classification(ids6, db="worms")
out7 <- classification(ids7, db="worms")
out8 <- classification(ids8, db="worms")
out9 <- classification(ids9, db="worms")
out10 <- classification(ids10, db="worms")
out11 <- classification(ids11, db="worms")
out12 <- classification(ids12, db="worms")
out13 <- classification(ids13, db="worms")

out <- c(out1, out2, out3, out4, out5, out6, out7, out8, out9, out10, out11, out12, out13)

results <- bind_rows(
  lapply(out, function(i){
    i %>%
      mutate(parent_id = lag(id, n = 1))
  })
) %>%
  distinct() %>%
  mutate(scientific_id = paste0("APHIA:", id)) %>%
  select(scientific_id, everything())

write_csv(results, "taxonomic-lookup/marinegeo_taxonomic_lookup.csv")

# Assemble classifications

library(tidyverse)

get_taxonomy_wide("APHIA:289919", results)

get_taxonomy_wide <- function(scientific_ids, adjacency_tbl) {

  get_ancestors <- function(node_id, tbl) {
    ancestors <- list()
    current_id <- node_id

    while (length(current_id) > 0 && !is.na(current_id)) {
      row <- tbl |> filter(id == current_id)
      if (nrow(row) == 0) break

      ancestors[[row$rank]] <- row$name
      current_id <- row$parent_id
    }

    ancestors
  }

  adjacency_tbl |>
    filter(scientific_id %in% scientific_ids) |>
    mutate(
      ancestors = pmap(list(id = id), \(id) get_ancestors(id, adjacency_tbl)),
      ancestors_df = map(ancestors, \(a) as_tibble(as.list(a)))
    ) |>
    select(scientific_id, ancestors_df) |>
    unnest(ancestors_df)
}


# Example adjacency table
taxonomy <- tribble(
  ~scientific_id, ~name,          ~rank,    ~id, ~parent_id,
  "sp001",        "Homo sapiens", "species",  1,  2,
  NA,             "Homo",         "genus",    2,  3,
  NA,             "Hominidae",    "family",   3,  4,
  NA,             "Primates",     "order",    4,  NA,
  "sp002",        "Pan troglodytes", "species", 5, 2
)

get_taxonomy_wide(c("sp001", "sp002"), taxonomy)



## Functional Group Lookup ####

read_csv(list.files("functional-group-lookup/", full.names = T))
