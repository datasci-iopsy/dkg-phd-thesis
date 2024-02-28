library(simstudy)
library(ggplot2)

# clean envr
rm(list = ls())

# define the outcome
simstudy::defDataAdd(
    varname = "resp", 
    dist = "normal", 
    formula = "5 + 2.5*period + 1.5*T + 3.5*period*T + e"
    ) -> 
    y_def

# define the correlated errors

c(0, 0, 0) -> mu
rep(sqrt(3), 3) -> sigma

# generate correlated data for each id and assign treatment

simstudy::genCorData(9, mu = mu, sigma = sigma, rho = .7, corstr = "cs") -> dt_cor
dt_cor
simstudy::trtAssign(dt_cor, nTrt = 3, balanced = TRUE, grpName = "T") -> dt_cor
dt_cor

# create longitudinal data set and generate outcome based on definition

simstudy::addPeriods(
    dt_cor, 
    nPeriods = 3, 
    idvars = "id", 
    timevars = c("V1","V2", "V3"), 
    timevarName = "e"
    ) -> 
    long_dat
long_dat

simstudy::addColumns(y_def, long_dat) -> long_dat
long_dat

long_dat[, T := factor(T, labels = c("No", "Maybe", "Yes"))]
long_dat

# look at the data, outcomes should appear more correlated, 
# lines a bit straighter

ggplot2::ggplot(data = long_dat, aes(x = factor(period), y = resp)) + 
    ggplot2::geom_line(aes(color = T, group = id)) +
    ggplot2::scale_color_manual(values = c("red", "blue", "green")) +
    ggplot2::xlab("Time")

