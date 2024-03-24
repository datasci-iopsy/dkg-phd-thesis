# Create three lists, each containing four distinct vectors
list1 <- list(a = 1:5, b = 6:10, c = 11:15, d = 16:20)
list2 <- list(e = 21:25, f = 26:30, g = 31:35, h = 36:40)
list3 <- list(i = 41:45, j = 46:50, k = 51:55, l = 56:60)

# Combine the three lists into a master list
master_list <- list(list1, list2, list3)

# Custom function to process the vectors
custom_function <- function(vec1, vec2, vec3) {
  # Custom processing logic goes here
  result <- vec1 * vec2 + vec3
  return(result)
}

# Loop over each list within the master list and apply the custom function using vectorization
result_list <- lapply(master_list, function(lst) {
  # Extract vectors from the list
  vec1 <- lst[[1]]
  vec2 <- lst[[2]]
  vec3 <- lst[[3]]
  
  # Apply the custom function using vectorization
  result <- custom_function(vec1, vec2, vec3)
  
  # Return the result
  return(result)
})

# Print the result list
print(result_list)
