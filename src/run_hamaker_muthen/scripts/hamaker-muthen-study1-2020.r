######################################
#### SIMULATE DATA WITH DIFFERENT ####
###### WITHIN AND BETWEEN SLOPES #####
######################################

rm(list = ls())
library(lme4)
set.seed(3859)

N <- 5000 # number of clusters
n <- 4 # number of observations within a cluster

Y <- matrix(, N, n) # to store the outcome
X <- matrix(, N, n) # to store the predictor
X.TrueCent <- matrix(, N, n) # to store the true centered predictor


########################
#### SET PARAMETER VALUES ####
########################

# PREDICTOR
sdX.within <- sqrt(1) # within-person variance
sdX.between <- sqrt(4) # between-person variance

# INTERCEPT LEVEL 2
g.00 <- 0 # Grand intercept
g.01 <- 2 # between-cluster slope
sd.u0 <- 1 # SD of residuals intercept at level 2

# SLOPE LEVEL 2
g.10 <- 1 # fixed within-cluster slope
sd.u1 <- 0 # SD of within-cluster slope at level 2

# RESIDUALS AT LEVEL 1
sd.e <- 1 # residual SD at level 1

#######################
#### SIMULATE DATA ####
#######################

for (j in 1:N) { # sample mean on x in cluster j
    X.mean.j <- rnorm(1, mean = 0, sd = sdX.between)
    # sample x in cluster j
    X.j <- rnorm(n, mean = X.mean.j, sd = sdX.within)
    X[j, ] <- X.j
    # sample slope in cluster j (here identical across individuals)
    b1.j <- rnorm(1, g.10, sd.u1)
    # sample intercept in cluster j (level 2 expression)
    b0.j <- rnorm(1, g.00, sd.u0) + g.01 * X.mean.j
    # sample y (level 1 expression)
    Y[j, ] <- b0.j + b1.j * (X.j - X.mean.j) + rnorm(n, 0, sd.e)
}

########################
### DATA PREPARATION ###
########################

Y <- c(t(Y))
X <- c(t(X))
Cluster <- rep(1:N, each = n)
Time <- rep(1:n, N)

#####################################
### ESTIMATE SAMPLE CLUSTER MEANS ###
###### AND CENTER X WITH THIS #######
#####################################

cluster.means <- NA
cluster.j <- 0
for (j in 1:N) {
    cluster.mean <- rep(mean(X[((cluster.j * n) + 1):((cluster.j * n) + n)]), n)
    cluster.means <- c(cluster.means, cluster.mean)
    cluster.j <- cluster.j + 1
}
cluster.means <- as.vector(cluster.means)[-1]

X.cent <- X - cluster.means
data.cent <- as.data.frame(cbind(Y, X.cent, X, Cluster, cluster.means))

########################
### ESTIMATE MODELS ####
########################

# L1: RAW X (RE MODEL)
mod0 <- lmer(Y ~ X + (1 | Cluster), data = data.cent, REML = F)
parameters::model_parameters(mod0)
# L2: CENTERED X (FE MODEL)
summary(lmer(Y ~ X.cent + (1 | Cluster), data = data.cent, REML = F))

# L3a: CENTERED X PLUS SAMPLE MEANS ON X (WITHIN-BETWEEN MODEL)
mod_l3b = lmer(Y ~ X.cent + cluster.means + (1 | Cluster), data = data.cent, REML = F)
parameters::model_parameters(mod_l3b)
# L4: RAW X PLUS SAMPLE MEANS ON X (MUNDLAK'S CONTEXTUAL MODEL)
summary(lmer(Y ~ X + cluster.means + (1 | Cluster), data = data.cent, REML = F))

##################
### WRITE DATA ###
##################

write.table(cbind(round(data.cent, 5), Time),
    file = "BWdataT4.dat", col.names = FALSE, row.names = FALSE
)
