gen_cor_matrix <- function(num_vars, cors, mu, n = 10) {
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

    df <- as.data.frame(MASS::mvrnorm(n = n, mu = mu, Sigma = cor_matrix))
    df$id <- seq_len(nrow(df))
    df <- df[, c((num_vars + 1), 1:num_vars)]
    return(df)
}

num_vars <- 4
cors <- c(0.56, -0.31, 0.37, -0.44, 0.51, -0.25)
mu <- c(2.54, 2.03, 3.88, 1.97)
n <- 100
dat <- gen_cor_matrix(
    num_vars = num_vars,
    cors = cors,
    mu = mu,
    n = 100
)
head(dat)

dat <- setNames(dat, c("id", "thwrt", "burn", "posaf", "negaf"))
head(dat)
