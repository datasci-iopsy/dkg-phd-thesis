library(tidyverse)
library(simstudy)
library(brms) # masks stats::ar
library(lmerTest)

rm(list = ls())

#### simulation process ####
# define response variable
simstudy::defDataAdd(
    varname = "burn", 
    dist = "normal", 
    formula = "2.80 + 0.60*time_pt + -0.40*comp + -0.23*auto + -0.30*rel", 
    variance = 1
    ) ->
    resp_def
resp_def

# generate correlated data
list() -> cor_params_ls # list comprising sim params

# enumerate params
cor_params_ls$n = 1000
cor_params_ls$mu = c(2.50, 2.35, 2.25)
cor_params_ls$sigma = c(0.80, 0.77, 0.65)
cor_params_ls$rho = 0.4
cor_params_ls$var_nms = c("comp", "auto", "rel")

# generate data
set.seed(8762) # set seed
simstudy::genCorData(
    idname = "emp_id",
    n = cor_params_ls$n,
    mu = cor_params_ls$mu, 
    sigma = cor_params_ls$sigma,
    rho = cor_params_ls$rho, 
    corstr = "cs",
    cnames = cor_params_ls$var_nms
) ->
    sim_cor_dat
sim_cor_dat

# create repeated measures design
simstudy::addPeriods(
    sim_cor_dat, 
    nPeriods = 3, 
    idvars = "emp_id", 
    perName = "time_pt", 
    timeid = "time_id",
    timevarName = "e"
) -> 
    long_dat
long_dat

# add response var to df
set.seed(9829)
simstudy::addColumns(resp_def, long_dat) -> final_dat

final_dat %>% 
    tibble::as_tibble() %>% 
    ggplot2::ggplot(aes(x = comp, y = eng)) +
    ggplot2::geom_point() -> p1

final_dat %>% 
    tibble::as_tibble() %>% 
    ggplot2::ggplot(aes(x = auto, y = eng)) +
    ggplot2::geom_point() -> p2

final_dat %>% 
    tibble::as_tibble() %>% 
    ggplot2::ggplot(aes(x = rel, y = eng)) +
    ggplot2::geom_point() -> p3

patchwork::wrap_plots(p1, p2, p3)

# ggplot(data      = final_dat,
#        aes(x     = comp,
#            y     = eng,
#            col   = time_pt,
#            group = time_pt
#            ))+ #to add the colours for different classes
#     geom_point(size     = 1.2,
#                alpha    = .8,
#                position = "jitter")+ #to add some random noise for plotting purposes
#     theme_minimal()+
#     theme(legend.position = "none")+
#     scale_color_gradientn(colours = rainbow(100))+
#     geom_smooth(method = lm,
#                 se     = FALSE,
#                 linewidth   = .5, 
#                 alpha  = .8) # to add regression line
#     # labs(title    = "Popularity vs. Extraversion",
#     #      subtitle = "add colours for different classes and regression lines")

# intercepts-only model
lm(eng ~ 1, data = final_dat) -> mod0_lmer
brms::brm(eng ~ 1, data = final_dat) -> mod0_brm

summary(mod0_lmer)
summary(mod0_brm)

broom.mixed::tidy(mod0_lmer)
broom.mixed::tidy(mod0_brm)

performance::icc(mod0_lmer)
performance::icc(mod0_brm)

lmerTest::lmer(eng ~ 1 + comp + auto + rel + (1 + time_pt | emp_id), data = final_dat) -> mod1_lmer
brms::brm(depress ~ 1 + comp + auto + rel + (1 + time_pt | emp_id), data = final_dat, control = list(adapt_delta = .95)) -> mod1_brm

summary(mod1_lmer)
summary(mod1_brm)

broom.mixed::tidy(mod1_lmer)
broom.mixed::tidy(mod0_brm)

performance::icc(mod0_lmer)
performance::icc(mod0_brm)

simstudy::addColumns(resp_def, long_dat) %>% 
    tibble::as_tibble() %>% 
    ggplot2::ggplot(aes(x = auto, y = burn)) +
    ggplot2::geom_point(aes(group = emp_id)) + 
    ggplot2::geom_smooth(method = "lm", aes(colour = factor(time_pt), group = factor(time_pt)))
# ggplot2::facet_wrap(vars(time_pt))
