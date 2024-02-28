# simstudy::defDataAdd(varname = "burn", dist = "normal", formula = 2.06, variance = .45)
#     resp_def
simstudy::defData(
    varname = "e", 
    dist = "normal", 
    formula = 0, 
    variance = sqrt(3)
) -> 
    rand_effect_def
rand_effect_def

simstudy::defDataAdd(
    varname = "burn", 
    dist = "normal", 
    formula = "2.06 + 1.5*time_pt + 1*comp + 1*auto + 1*rel + e", 
    variance = 1
) ->
    resp_def
resp_def

# generate data 
set.seed(8762) # set seed
simstudy::genData(18, rand_effect_def, id = "emp_id") -> ind_dat
ind_dat

# add repeated measures for individuals
simstudy::addPeriods(
    dtName = ind_dat, 
    nPeriods = 3, 
    idvars = "emp_id"
) -> 
    long_dat1
long_dat1

simstudy::addColumns(dtDefs = rand_effect_def, long_dat)

simstudy::defDataAdd(
    # dtDefs = NULL, 
    varname = "eng", 
    dist = "normal", 
    formula = "2 + 1.5*period + 1*comp*period + 1*auto*period + 1*rel*period", 
    variance = 3,
) ->
    sim_def

# define covariate: competency
simstudy::defData(
    dtDefs = sim_def,
    varname = "comp", 
    dist = "normal", 
    formula = , 
    variance = 3
) ->
    sim_def

# define covariate: autonomy
simstudy::defData(
    dtDefs = sim_def,
    varname = "auto", 
    dist = "normal", 
    formula = "2 + 1.5*period + 1*comp*period + 1*auto*period + 1*rel*period", 
    variance = 3
) ->
    sim_def

# definte covariate: relatedness
simstudy::defData(
    dtDefs = sim_defL,
    varname = "rel", 
    dist = "normal", 
    formula = "2 + 1.5*period + 1*comp*period + 1*auto*period + 1*rel*period", 
    variance = 3
) ->
    # sim_def
    
    # generate a "blank" data.table w/ n obs
    set.seed(1879) # set seed
simstudy::genData(9, id = "emp_id") -> ind_dat

# generate longitudinal data w/ 3 time points for each individual
simstudy::addPeriods(
    ind_dat, 
    nPeriods = 3, 
    idvars = "emp_id"
) -> 
    long_dat

# add response variable to df
simstudy::addColumns(dtDefs = resp_var, long_dat) -> dat

simstudy::defData(dtDefs = sim_def, varname = "eng_t1", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "eng_t2", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def
sim_def

set.seed(1879)
simstudy::genData(n = 1000, dtDefs = sim_def, id = "emp_id") -> sim_cross_sec
simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("eng_t0", "eng_t1", "eng_t2"), timevarName = "new_eng") ->
    t_eng; t_eng

###
simstudy::defData(dtDefs = sim_def, varname = "comp_t0", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "comp_t1", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "comp_t2", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def
sim_def
set.seed(8762)
simstudy::genData(n = 1000, dtDefs = sim_def, id = "emp_id") -> sim_cross_sec
simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("comp_t0", "comp_t1", "comp_t2"), timevarName = "new_comp") ->
    t_comp; t_comp

###
simstudy::defData(dtDefs = sim_def, varname = "auto_t0", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "auto_t1", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "auto_t2", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def
sim_def
set.seed(9829)
simstudy::genData(n = 1000, dtDefs = sim_def, id = "emp_id") -> sim_cross_sec
simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("auto_t0", "auto_t1", "auto_t2"), timevarName = "new_auto") ->
    t_auto; t_auto

###
simstudy::defData(dtDefs = NULL, varname = "rel_t0", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "rel_t1", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def

simstudy::defData(dtDefs = sim_def, varname = "rel_t2", dist = "normal", formula = 3, variance = 1, id = "emp_id") ->
    sim_def
sim_def
set.seed(1425)
simstudy::genData(n = 1000, dtDefs = sim_def, id = "emp_id") -> sim_cross_sec
simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("rel_t0", "rel_t1", "rel_t2"), timevarName = "new_rel") ->
    t_rel; t_rel

# simstudy::defData(dtDefs = sim_def, varname = "comp", dist = "normal", formula = 3.75, variance = .25) -> 
#     sim_def
# 
# simstudy::defData(dtDefs = sim_def, varname = "auto", dist = "normal", formula = 3.5, variance = 1.5) -> 
#     sim_def
# 
# simstudy::defData(dtDefs = sim_def, varname = "rel" , dist = "normal", formula = 4.1, variance = .9) -> 
#     sim_def

# # preview
# sim_def
# 
# # sim data info
# class(sim_def)
# attributes(sim_def)

# # set seed
# set.seed(8762)
# 
# # generate sim data set
# simstudy::genData(n = 5, dtDefs = sim_def, id = "emp_id") -> sim_cross_sec
# sim_cross_sec
# 
# # add repeated measures data
# # simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = "intcp", timevarName = "t_intcp") #-> t_intcp
# simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("comp", "auto", "rel"), timevarName = "t_eng") -> 
#     t_eng; t_eng
# simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("eng", "auto", "rel"), timevarName = "t_comp") -> 
#     t_comp; t_comp
# simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("eng", "comp", "rel"), timevarName = "t_auto") -> 
#     t_auto; t_auto
# simstudy::addPeriods(sim_cross_sec, nPeriods = 3, idvars = "emp_id", timevars = c("eng", "comp", "auto"), timevarName = "t_rel") -> 
#     t_rel; t_rel

dplyr::select(t_eng, emp_id, period, new_eng) %>% 
    dplyr::left_join(select(t_comp, emp_id, period, new_comp), by = c("emp_id", "period")) %>% 
    dplyr::left_join(select(t_auto, emp_id, period, new_auto), by = c("emp_id", "period")) %>% 
    dplyr::left_join(select(t_rel, emp_id, period, new_rel), by = c("emp_id", "period")) %>% 
    tibble::as_tibble() %>% 
    dplyr::mutate(emp_id = as.character(emp_id), period = as.character(period)) ->
    x
x
summary(x)
# simstudy::addPeriods(sim_cross_sec, nPeriods = 4, idvars = "emp_id", timevars = c("eng", "comp", "auto", "rel"), timevarName = "Y")
# simstudy::addPeriods(sim_cross_sec)

# long format
x %>% 
    tidyr::pivot_longer(-c(emp_id, period), values_to = "mean", names_to = "var_nm") -> 
    long_x
long_x

long_x %>% 
    ggplot2::ggplot(aes(x = mean, after_stat(density), colour = var_nm)) +
    ggplot2::geom_freqpoly() + 
    ggplot2::facet_grid(vars(period))
# ggplot2::facet_wrap(vars(var_nm))

dplyr::filter(x, emp_id %in% as.character(1:20)) %>% 
    ggplot2::ggplot(aes(x = period, y = new_eng, group = emp_id)) +
    ggplot2::geom_point() + 
    ggplot2::geom_smooth(method = lm) + 
    ggplot2::facet_wrap(vars(emp_id))

brm(new_eng ~ period, data = x) -> mod0
conditional_effects(mod0)

brm(new_eng ~ 1 + period + (1 + period | emp_id), data = x) -> mod1
plot(mod1)
summary(mod1)

brm(new_eng ~ new_comp + new_auto + new_rel + (period | emp_id), data = x, chains = 4, cores = 10, control = list(adapt_delta = .95)) -> mod2

# ggplot(data = x, aes(x = new_comp, y = new_eng, colour = as.factor(period))) + geom_point(position = "jitter") + geom_smooth(method = lm)


brms::brm(
    new_eng ~ 1 + (1 | period), 
    data = x, 
    warmup = 2500, 
    iter = 50000, 
    chains = 2, 
    init = "random", 
    cores = 10, 
    seed = 6221, 
    control = list(adapt_delta = .99)
) -> 
    mod0


# # list of variables and corresponding params
# list() -> params_ls

# # set seed for sim defs
# set.seed(1879)

# # response var - engagement (eng)
# params_ls$eng_n = 1000
# params_ls$eng_vct = sample(1:5, size = params_ls$eng_n, replace = TRUE)
# params_ls$eng_mean = mean(params_ls$eng_vct, size = params_ls$eng_n, replace = TRUE)
# params_ls$eng_sd = sd(params_ls$eng_vct)
# params_ls
# 
# # covariate - competency (comp)
# params_ls$comp_n = 1000
# params_ls$comp_vct = sample(1:5, size = params_ls$comp_n, replace = TRUE)
# params_ls$comp_mean = mean(params_ls$comp_vct, size = params_ls$comp_n, replace = TRUE)
# params_ls$comp_sd = sd(params_ls$comp_vct)
# params_ls
# 
# # covariate - autonomy (auto)
# params_ls$auto_n = 1000
# params_ls$auto_vct = sample(1:5, size = params_ls$auto_n, replace = TRUE)
# params_ls$auto_mean = mean(params_ls$auto_vct, size = params_ls$auto_n, replace = TRUE)
# params_ls$auto_sd = sd(params_ls$auto_vct)
# params_ls
# 
# # covariate - relatedness (rel)
# params_ls$rel_n = 1000
# params_ls$rel_vct = sample(1:5, size = params_ls$rel_n, replace = TRUE)
# params_ls$rel_mean = mean(params_ls$rel_vct, size = params_ls$rel_n, replace = TRUE)
# params_ls$rel_sd = sd(params_ls$rel_vct)
# params_ls
# 
# # response var
# simstudy::defData(dtDefs = NULL, varname = "eng", dist = "normal", formula = params_ls$eng_mean, variance = var(params_ls$eng_vct), id = "emp_id") -> 
#     sim_def

# simstudy::defData(dtDefs = sim_def, varname = "intcp", dist = "normal", formula = 3, variance = 1) -> 
#     sim_def

# simstudy::defData(dtDefs = sim_def, varname = "comp", dist = "normal", formula = params_ls$comp_mean, variance = var(params_ls$comp_vct)) -> 
#     sim_def
# 
# simstudy::defData(dtDefs = sim_def, varname = "auto", dist = "normal", formula = params_ls$auto_mean, variance = var(params_ls$auto_vct)) -> 
#     sim_def
# 
# simstudy::defData(dtDefs = sim_def, varname = "rel" , dist = "normal", formula = params_ls$rel_mean, variance = var(params_ls$rel_vct)) -> 
#     sim_def
