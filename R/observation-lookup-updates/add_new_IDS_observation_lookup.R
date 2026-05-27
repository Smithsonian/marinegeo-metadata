# scientific_name <- "red branching macroalgae"
# scientific_id <- "FUNCTIONAL:RED_BRANCHING_ALGAE"
# add_new_observation_id(scientific_name, scientific_id)

add_new_observation_id <- function(scientific_name, scientific_id){
  
  if(length(scientific_name) > 1){
    stop("Only one scientific_name should be supplied to this function")
  }
  
  if(length(scientific_id) > 1){
    stop("Only one scientific ID should be supplied to this function")
  }
  
  if(!is.character(scientific_name)){
    stop("`scientific_name` must be a character vector.")
  }
  
  if(!is.character(scientific_id)){
    stop("`scientific_id` must be a character vector.")
  }
  
  obs_df <- readr::read_csv(list.files(
    "taxonomy-and-functional-groups/observation-lookup/", full.names = T),
    show_col_types = FALSE
  )
  
  pre_existing_ids <- obs_df |>
    dplyr::filter(scientific_name == !!scientific_name)
  
  if(nrow(pre_existing_ids) > 0){
    stop("The supplied scientific name is already present in observation lookup table")
  }
  
  pre_existing_sci_ids <- obs_df |>
    dplyr::filter(scientific_id == !!scientific_id)
  
  if(nrow(pre_existing_sci_ids) > 0){
    cat(
      paste(
        "Scientific ID already present in observation lookup table.\n",
        "Note that this is not necessarily an error, but should be reviewed:\n",
        paste(capture.output(pre_existing_sci_ids), collapse = "\n")
      )
    )
    
    response <- readline(prompt = "Continue adding observation (y/n)?")
    
    if(tolower(response) == "n"){
      stop()
    }
  }
  
  new_row <- tibble::tibble(
    scientific_name = !!scientific_name,
    scientific_id = !! scientific_id
  )
  
  tryCatch({
    
    obs_df_updated <- obs_df |>
      dplyr::bind_rows(new_row) |>
      dplyr::arrange(scientific_id)
    
    readr::write_csv(obs_df_updated, "taxonomy-and-functional-groups/observation-lookup/marinegeo_observation_ids.csv")
    
  }, error = function(e) {
    
    message("ERROR UPDATING OBSERVATION LOOKUP TABLE: ", conditionMessage(e))
    
  })
 
  tryCatch({
    
    cat(
      paste(
        "Verify new observation successfully added to observation lookup table:\n",
        paste(capture.output(
          dplyr::anti_join(
            readr::read_csv(list.files(
              "taxonomy-and-functional-groups/observation-lookup/", full.names = T),
              show_col_types = FALSE
            ), 
            obs_df, dplyr::join_by(scientific_name, scientific_id))
        ), collapse = "\n")
      )
    )
    
  }, error = function(e) {
    
    message("ERROR VERIFYING OBSERVATION LOOKUP TABLE UPDATE: ", conditionMessage(e))
    
  })
  
}


