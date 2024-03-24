library(here)
library(dplyr) # masks stats::filter, lag; base::intersect, setdiff, setequal, union
library(tibble)
library(purrr)
library(readr)

here::i_am("./src/bayes_sdt_mlm/scripts/00-gen-syn-data.R")
here::here()

gen_cor_matrix <- function(num_vars, cors, mu, n) {
    # Check if the length of the correlations vector matches the expected length
    if (length(cors) != num_vars * (num_vars - 1) / 2) {
        stop("Length of 'correlations' vector should be (num_vars * (num_vars - 1)) / 2.")
    }

    # num_vars <- num_vars

    # Initialize a matrix to store correlation values
    cor_matrix <- diag(1, num_vars, num_vars) # Diagonal elements are 1

    # Fill the upper triangle of the matrix with correlations
    idx <- 1
    for (i in 1:(num_vars - 1)) {
        for (j in (i + 1):num_vars) {
            cor_matrix[i, j] <- cors[idx]
            cor_matrix[j, i] <- cors[idx] # Since it's symmetric
            idx <- idx + 1
        }
    }

    cor_matrix <- as.matrix(cor_matrix)
    # return(cor_matrix)

    if (length(mu) != num_vars) {
        stop("Length of 'mu' vector must = num_vars")
    }

    df <- tibble::as_tibble(MASS::mvrnorm(n = n, mu = mu, Sigma = cor_matrix))
    df$id <- seq_len(nrow(df))
    df <- df[, c((num_vars + 1), 1:num_vars)]
    return(df)
}

main_ls <- list(
    t1 = list(num_vars = 4, cors = c(0.84, 0.68, 0.53, 0.82, 0.74, 0.86), mu = c(5.10, 5.35, 4.26, 3.67), n = 500),
    t2 = list(num_vars = 4, cors = c(0.79, 0.62, 0.50, 0.80, 0.72, 0.81), mu = c(4.92, 5.02, 3.99, 3.29), n = 500),
    t3 = list(num_vars = 4, cors = c(0.82, 0.66, 0.52, 0.84, 0.73, 0.82), mu = c(5.2, 5.61, 4.81, 3.84), n = 500)
)

gen_dat <- function(outer_ls) {
    purrr::map(outer_ls, function(inner_ls) {
        # Extract vectors from the list
        num_vars <- inner_ls$num_vars
        cors <- inner_ls$cors
        mu <- inner_ls$mu
        n <- inner_ls$n

        # Apply the custom function using vectorization
        syn_df_ls <- gen_cor_matrix(
            num_vars = num_vars,
            cors = cors,
            mu = mu,
            n = n
        )

        # return the result
        return(syn_df_ls)
    })
}

df <- gen_dat(main_ls)
head(df)

col_nms <- c("intro", "iden", "intri", "eng")

dat <- dplyr::bind_rows(df) %>%
    dplyr::rename_with(~col_nms, starts_with("V")) %>%
    dplyr::arrange(id) %>%
    dplyr::mutate(
        time = as.integer(row_number() - 1),
        .after = id,
        .by = id
    )
summary(dat)
dat

readr::write_csv(dat, "./src/data/processed/syn-dat.csv")
