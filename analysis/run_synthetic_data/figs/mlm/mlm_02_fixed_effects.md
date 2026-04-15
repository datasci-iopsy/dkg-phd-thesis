|effect |term                                                 | estimate| std.error| statistic|     df|p.value | conf.low| conf.high|model                               |
|:------|:----------------------------------------------------|--------:|---------:|---------:|------:|:-------|--------:|---------:|:-----------------------------------|
|fixed  |(Intercept)                                          |   1.9199|    0.0262|   73.1498|  773.0|< .001  |   1.8684|    1.9714|Model 0: Unconditional Means        |
|fixed  |(Intercept)                                          |   1.9257|    0.0315|   61.0558| 1467.4|< .001  |   1.8638|    1.9876|Model 1: Fixed Time                 |
|fixed  |time_c                                               |  -0.0058|    0.0175|   -0.3324| 1547.0|0.7396  |  -0.0401|    0.0285|Model 1: Fixed Time                 |
|fixed  |(Intercept)                                          |   1.9257|    0.0322|   59.8411|  773.0|< .001  |   1.8625|    1.9889|Model 2: Random Slope               |
|fixed  |time_c                                               |  -0.0058|    0.0175|   -0.3318|  773.0|0.7401  |  -0.0402|    0.0286|Model 2: Random Slope               |
|fixed  |(Intercept)                                          |   1.9294|    0.0311|   62.1106| 1403.6|< .001  |   1.8685|    1.9903|Model 3: L1 Within-Person           |
|fixed  |time_c                                               |  -0.0095|    0.0166|   -0.5722| 1539.0|0.5673  |  -0.0421|    0.0231|Model 3: L1 Within-Person           |
|fixed  |pf_mean_within                                       |   0.1043|    0.0298|    3.5043| 1539.0|< .001  |   0.0459|    0.1627|Model 3: L1 Within-Person           |
|fixed  |cw_mean_within                                       |   0.0814|    0.0321|    2.5362| 1539.0|0.0113  |   0.0185|    0.1444|Model 3: L1 Within-Person           |
|fixed  |ee_mean_within                                       |   0.0713|    0.0276|    2.5863| 1539.0|0.0098  |   0.0172|    0.1254|Model 3: L1 Within-Person           |
|fixed  |comp_mean_within                                     |   0.0610|    0.0288|    2.1180| 1539.0|0.0343  |   0.0045|    0.1175|Model 3: L1 Within-Person           |
|fixed  |auto_mean_within                                     |   0.0224|    0.0288|    0.7773| 1539.0|0.4371  |  -0.0341|    0.0790|Model 3: L1 Within-Person           |
|fixed  |relt_mean_within                                     |   0.0529|    0.0299|    1.7713| 1539.0|0.0767  |  -0.0057|    0.1115|Model 3: L1 Within-Person           |
|fixed  |meetings_count_within                                |   0.0232|    0.0452|    0.5125| 1539.0|0.6084  |  -0.0655|    0.1119|Model 3: L1 Within-Person           |
|fixed  |meetings_mins_within                                 |   0.0009|    0.0009|    0.9151| 1539.0|0.3603  |  -0.0010|    0.0027|Model 3: L1 Within-Person           |
|fixed  |(Intercept)                                          |   0.4265|    0.1153|    3.7001|  797.6|< .001  |   0.2002|    0.6527|Model 4: L1 Within + Between        |
|fixed  |time_c                                               |  -0.0095|    0.0166|   -0.5722| 1539.0|0.5673  |  -0.0421|    0.0231|Model 4: L1 Within + Between        |
|fixed  |pf_mean_within                                       |   0.1043|    0.0298|    3.5043| 1539.0|< .001  |   0.0459|    0.1627|Model 4: L1 Within + Between        |
|fixed  |cw_mean_within                                       |   0.0814|    0.0321|    2.5362| 1539.0|0.0113  |   0.0185|    0.1444|Model 4: L1 Within + Between        |
|fixed  |ee_mean_within                                       |   0.0713|    0.0276|    2.5863| 1539.0|0.0098  |   0.0172|    0.1254|Model 4: L1 Within + Between        |
|fixed  |comp_mean_within                                     |   0.0610|    0.0288|    2.1180| 1539.0|0.0343  |   0.0045|    0.1175|Model 4: L1 Within + Between        |
|fixed  |auto_mean_within                                     |   0.0224|    0.0288|    0.7773| 1539.0|0.4371  |  -0.0341|    0.0790|Model 4: L1 Within + Between        |
|fixed  |relt_mean_within                                     |   0.0529|    0.0299|    1.7713| 1539.0|0.0767  |  -0.0057|    0.1115|Model 4: L1 Within + Between        |
|fixed  |meetings_count_within                                |   0.0232|    0.0452|    0.5125| 1539.0|0.6084  |  -0.0655|    0.1119|Model 4: L1 Within + Between        |
|fixed  |meetings_mins_within                                 |   0.0009|    0.0009|    0.9151| 1539.0|0.3603  |  -0.0010|    0.0027|Model 4: L1 Within + Between        |
|fixed  |pf_mean_between                                      |   0.1817|    0.0515|    3.5252|  765.0|< .001  |   0.0805|    0.2829|Model 4: L1 Within + Between        |
|fixed  |cw_mean_between                                      |   0.1497|    0.0551|    2.7183|  765.0|0.0067  |   0.0416|    0.2578|Model 4: L1 Within + Between        |
|fixed  |ee_mean_between                                      |   0.0710|    0.0485|    1.4639|  765.0|0.1436  |  -0.0242|    0.1661|Model 4: L1 Within + Between        |
|fixed  |comp_mean_between                                    |   0.0329|    0.0522|    0.6302|  765.0|0.5288  |  -0.0695|    0.1353|Model 4: L1 Within + Between        |
|fixed  |auto_mean_between                                    |   0.1035|    0.0550|    1.8831|  765.0|0.0601  |  -0.0044|    0.2114|Model 4: L1 Within + Between        |
|fixed  |relt_mean_between                                    |   0.1214|    0.0591|    2.0558|  765.0|0.0401  |   0.0055|    0.2374|Model 4: L1 Within + Between        |
|fixed  |meetings_count_between                               |  -0.0757|    0.0661|   -1.1459|  765.0|0.2522  |  -0.2055|    0.0540|Model 4: L1 Within + Between        |
|fixed  |meetings_mins_between                                |   0.0028|    0.0013|    2.0890|  765.0|0.037   |   0.0002|    0.0055|Model 4: L1 Within + Between        |
|fixed  |(Intercept)                                          |   0.4121|    0.1158|    3.5584|  792.1|< .001  |   0.1848|    0.6394|Model 5: L1 + L2 Study Variables    |
|fixed  |time_c                                               |  -0.0095|    0.0166|   -0.5722| 1539.0|0.5673  |  -0.0421|    0.0231|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_within                                       |   0.1043|    0.0298|    3.5043| 1539.0|< .001  |   0.0459|    0.1627|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_within                                       |   0.0814|    0.0321|    2.5362| 1539.0|0.0113  |   0.0185|    0.1444|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_within                                       |   0.0713|    0.0276|    2.5863| 1539.0|0.0098  |   0.0172|    0.1254|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_within                                     |   0.0610|    0.0288|    2.1180| 1539.0|0.0343  |   0.0045|    0.1175|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_within                                     |   0.0224|    0.0288|    0.7773| 1539.0|0.4371  |  -0.0341|    0.0790|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_within                                     |   0.0529|    0.0299|    1.7713| 1539.0|0.0767  |  -0.0057|    0.1115|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_within                                |   0.0232|    0.0452|    0.5125| 1539.0|0.6084  |  -0.0655|    0.1119|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_mins_within                                 |   0.0009|    0.0009|    0.9151| 1539.0|0.3603  |  -0.0010|    0.0027|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_between                                      |   0.1806|    0.0516|    3.4994|  760.0|< .001  |   0.0793|    0.2819|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_between                                      |   0.1508|    0.0552|    2.7346|  760.0|0.0064  |   0.0426|    0.2591|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_between                                      |   0.0698|    0.0486|    1.4378|  760.0|0.1509  |  -0.0255|    0.1652|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_between                                    |   0.0320|    0.0523|    0.6118|  760.0|0.5408  |  -0.0707|    0.1346|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_between                                    |   0.1060|    0.0550|    1.9261|  760.0|0.0545  |  -0.0020|    0.2140|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_between                                    |   0.1232|    0.0591|    2.0832|  760.0|0.0376  |   0.0071|    0.2393|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_between                               |  -0.0657|    0.0665|   -0.9880|  760.0|0.3235  |  -0.1962|    0.0648|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_mins_between                                |   0.0026|    0.0014|    1.9548|  760.0|0.051   |   0.0000|    0.0053|Model 5: L1 + L2 Study Variables    |
|fixed  |pa_mean_c                                            |  -0.0217|    0.0351|   -0.6179|  760.0|0.5368  |  -0.0906|    0.0472|Model 5: L1 + L2 Study Variables    |
|fixed  |na_mean_c                                            |   0.0025|    0.0335|    0.0755|  760.0|0.9399  |  -0.0633|    0.0684|Model 5: L1 + L2 Study Variables    |
|fixed  |br_mean_c                                            |   0.0197|    0.0459|    0.4295|  760.0|0.6677  |  -0.0704|    0.1098|Model 5: L1 + L2 Study Variables    |
|fixed  |vio_mean_c                                           |   0.0065|    0.0409|    0.1596|  760.0|0.8733  |  -0.0737|    0.0867|Model 5: L1 + L2 Study Variables    |
|fixed  |js_mean_c                                            |   0.0610|    0.0310|    1.9685|  760.0|0.0494  |   0.0002|    0.1218|Model 5: L1 + L2 Study Variables    |
|fixed  |(Intercept)                                          |   0.4544|    0.3306|    1.3745|  744.8|0.1697  |  -0.1946|    1.1033|Model 6: Full Model with Covariates |
|fixed  |time_c                                               |  -0.0095|    0.0166|   -0.5722| 1539.0|0.5673  |  -0.0421|    0.0231|Model 6: Full Model with Covariates |
|fixed  |pf_mean_within                                       |   0.1043|    0.0298|    3.5043| 1539.0|< .001  |   0.0459|    0.1627|Model 6: Full Model with Covariates |
|fixed  |cw_mean_within                                       |   0.0814|    0.0321|    2.5362| 1539.0|0.0113  |   0.0185|    0.1444|Model 6: Full Model with Covariates |
|fixed  |ee_mean_within                                       |   0.0713|    0.0276|    2.5863| 1539.0|0.0098  |   0.0172|    0.1254|Model 6: Full Model with Covariates |
|fixed  |comp_mean_within                                     |   0.0610|    0.0288|    2.1180| 1539.0|0.0343  |   0.0045|    0.1175|Model 6: Full Model with Covariates |
|fixed  |auto_mean_within                                     |   0.0224|    0.0288|    0.7773| 1539.0|0.4371  |  -0.0341|    0.0790|Model 6: Full Model with Covariates |
|fixed  |relt_mean_within                                     |   0.0529|    0.0299|    1.7713| 1539.0|0.0767  |  -0.0057|    0.1115|Model 6: Full Model with Covariates |
|fixed  |meetings_count_within                                |   0.0232|    0.0452|    0.5125| 1539.0|0.6084  |  -0.0655|    0.1119|Model 6: Full Model with Covariates |
|fixed  |meetings_mins_within                                 |   0.0009|    0.0009|    0.9151| 1539.0|0.3603  |  -0.0010|    0.0027|Model 6: Full Model with Covariates |
|fixed  |pf_mean_between                                      |   0.1979|    0.0527|    3.7563|  741.0|< .001  |   0.0945|    0.3014|Model 6: Full Model with Covariates |
|fixed  |cw_mean_between                                      |   0.1430|    0.0555|    2.5782|  741.0|0.0101  |   0.0341|    0.2519|Model 6: Full Model with Covariates |
|fixed  |ee_mean_between                                      |   0.0631|    0.0489|    1.2900|  741.0|0.1975  |  -0.0329|    0.1592|Model 6: Full Model with Covariates |
|fixed  |comp_mean_between                                    |   0.0272|    0.0533|    0.5098|  741.0|0.6103  |  -0.0775|    0.1318|Model 6: Full Model with Covariates |
|fixed  |auto_mean_between                                    |   0.1025|    0.0559|    1.8360|  741.0|0.0668  |  -0.0071|    0.2122|Model 6: Full Model with Covariates |
|fixed  |relt_mean_between                                    |   0.1211|    0.0597|    2.0273|  741.0|0.043   |   0.0038|    0.2383|Model 6: Full Model with Covariates |
|fixed  |meetings_count_between                               |  -0.0748|    0.0668|   -1.1204|  741.0|0.2629  |  -0.2058|    0.0563|Model 6: Full Model with Covariates |
|fixed  |meetings_mins_between                                |   0.0030|    0.0014|    2.1863|  741.0|0.0291  |   0.0003|    0.0056|Model 6: Full Model with Covariates |
|fixed  |pa_mean_c                                            |  -0.0259|    0.0354|   -0.7306|  741.0|0.4653  |  -0.0955|    0.0437|Model 6: Full Model with Covariates |
|fixed  |na_mean_c                                            |  -0.0045|    0.0342|   -0.1327|  741.0|0.8945  |  -0.0717|    0.0626|Model 6: Full Model with Covariates |
|fixed  |br_mean_c                                            |   0.0219|    0.0463|    0.4721|  741.0|0.637   |  -0.0690|    0.1127|Model 6: Full Model with Covariates |
|fixed  |vio_mean_c                                           |   0.0035|    0.0412|    0.0855|  741.0|0.9319  |  -0.0774|    0.0844|Model 6: Full Model with Covariates |
|fixed  |js_mean_c                                            |   0.0684|    0.0311|    2.1952|  741.0|0.0285  |   0.0072|    0.1295|Model 6: Full Model with Covariates |
|fixed  |age_c                                                |   0.0043|    0.0025|    1.7427|  741.0|0.0818  |  -0.0005|    0.0092|Model 6: Full Model with Covariates |
|fixed  |job_tenure3 to 5 years                               |   0.0504|    0.0626|    0.8049|  741.0|0.4211  |  -0.0725|    0.1732|Model 6: Full Model with Covariates |
|fixed  |job_tenureLess than a year                           |  -0.0226|    0.0749|   -0.3019|  741.0|0.7628  |  -0.1697|    0.1245|Model 6: Full Model with Covariates |
|fixed  |job_tenureMore than 5 years                          |  -0.0275|    0.0618|   -0.4447|  741.0|0.6566  |  -0.1489|    0.0939|Model 6: Full Model with Covariates |
|fixed  |edu_lvlBachelor's degree                             |  -0.0929|    0.0935|   -0.9936|  741.0|0.3207  |  -0.2765|    0.0907|Model 6: Full Model with Covariates |
|fixed  |edu_lvlHigh school diploma or equivalent (e.g., GED) |  -0.1905|    0.1099|   -1.7339|  741.0|0.0833  |  -0.4061|    0.0252|Model 6: Full Model with Covariates |
|fixed  |edu_lvlMaster's degree                               |  -0.1446|    0.1060|   -1.3646|  741.0|0.1728  |  -0.3526|    0.0634|Model 6: Full Model with Covariates |
|fixed  |edu_lvlProfessional or doctorate degree              |  -0.2363|    0.1215|   -1.9440|  741.0|0.0523  |  -0.4749|    0.0023|Model 6: Full Model with Covariates |
|fixed  |edu_lvlSome college, no degree                       |  -0.0729|    0.1026|   -0.7105|  741.0|0.4776  |  -0.2744|    0.1285|Model 6: Full Model with Covariates |
|fixed  |edu_lvlSome high school, no diploma                  |  -0.0125|    0.2482|   -0.0505|  741.0|0.9597  |  -0.4998|    0.4747|Model 6: Full Model with Covariates |
|fixed  |edu_lvlVocational training                           |  -0.1663|    0.1285|   -1.2946|  741.0|0.1959  |  -0.4185|    0.0859|Model 6: Full Model with Covariates |
|fixed  |ethnicityArab, Middle Eastern, or North African      |  -0.1919|    0.3313|   -0.5793|  741.0|0.5626  |  -0.8422|    0.4584|Model 6: Full Model with Covariates |
|fixed  |ethnicityAsian                                       |   0.1862|    0.3014|    0.6179|  741.0|0.5368  |  -0.4055|    0.7780|Model 6: Full Model with Covariates |
|fixed  |ethnicityBlack or African American                   |   0.1776|    0.3000|    0.5919|  741.0|0.5541  |  -0.4114|    0.7665|Model 6: Full Model with Covariates |
|fixed  |ethnicityHispanic or Latino                          |   0.0698|    0.2977|    0.2346|  741.0|0.8146  |  -0.5146|    0.6543|Model 6: Full Model with Covariates |
|fixed  |ethnicityNative Hawaiian or other Pacific Islander   |   0.4000|    0.4369|    0.9154|  741.0|0.3603  |  -0.4578|    1.2577|Model 6: Full Model with Covariates |
|fixed  |ethnicityPrefer not to say                           |  -0.1048|    0.3426|   -0.3060|  741.0|0.7597  |  -0.7774|    0.5677|Model 6: Full Model with Covariates |
|fixed  |ethnicityTwo or more races                           |   0.1592|    0.3093|    0.5148|  741.0|0.6069  |  -0.4480|    0.7665|Model 6: Full Model with Covariates |
|fixed  |ethnicityWhite or Caucasian                          |   0.0445|    0.2939|    0.1514|  741.0|0.8797  |  -0.5325|    0.6215|Model 6: Full Model with Covariates |
