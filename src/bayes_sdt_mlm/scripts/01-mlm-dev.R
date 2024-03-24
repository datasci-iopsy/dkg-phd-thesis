library(lme4)
library(readr)

dat <- readr::read_csv("src/data/processed/syn-dat.csv")
summary(dat)
dat

x <- lm(eng ~ intro, iden, intri, data = dat)
summary(x)
plot(x)
mod0 <- lme4::lmer(eng ~ time + (1 | id), data = dat)
summary(mod0)
performance::icc(mod0)
