|effect |term                                                 | estimate| std.error| statistic|     df|p.value | conf.low| conf.high|model                               |
|:------|:----------------------------------------------------|--------:|---------:|---------:|------:|:-------|--------:|---------:|:-----------------------------------|
|fixed  |(Intercept)                                          |   1.9081|    0.0259|   73.6411|  790.0|< .001  |   1.8573|    1.9590|Model 0: Unconditional Means        |
|fixed  |(Intercept)                                          |   1.9138|    0.0311|   61.4945| 1497.5|< .001  |   1.8528|    1.9749|Model 1: Fixed Time                 |
|fixed  |time_c                                               |  -0.0057|    0.0172|   -0.3300| 1581.0|0.7414  |  -0.0395|    0.0281|Model 1: Fixed Time                 |
|fixed  |(Intercept)                                          |   1.9138|    0.0311|   61.4945| 1497.5|< .001  |   1.8528|    1.9749|Model 2: Random Slope               |
|fixed  |time_c                                               |  -0.0057|    0.0172|   -0.3300| 1581.0|0.7414  |  -0.0395|    0.0281|Model 2: Random Slope               |
|fixed  |(Intercept)                                          |   1.9167|    0.0307|   62.5285| 1432.5|< .001  |   1.8566|    1.9768|Model 3: L1 Within-Person           |
|fixed  |time_c                                               |  -0.0086|    0.0164|   -0.5238| 1573.0|0.6005  |  -0.0407|    0.0235|Model 3: L1 Within-Person           |
|fixed  |pf_mean_within                                       |   0.1043|    0.0295|    3.5351| 1573.0|< .001  |   0.0464|    0.1622|Model 3: L1 Within-Person           |
|fixed  |cw_mean_within                                       |   0.0801|    0.0317|    2.5217| 1573.0|0.0118  |   0.0178|    0.1423|Model 3: L1 Within-Person           |
|fixed  |ee_mean_within                                       |   0.0710|    0.0273|    2.5995| 1573.0|0.0094  |   0.0174|    0.1246|Model 3: L1 Within-Person           |
|fixed  |comp_mean_within                                     |   0.0589|    0.0286|    2.0623| 1573.0|0.0393  |   0.0029|    0.1150|Model 3: L1 Within-Person           |
|fixed  |auto_mean_within                                     |   0.0194|    0.0286|    0.6800| 1573.0|0.4966  |  -0.0366|    0.0755|Model 3: L1 Within-Person           |
|fixed  |relt_mean_within                                     |   0.0583|    0.0296|    1.9700| 1573.0|0.049   |   0.0003|    0.1163|Model 3: L1 Within-Person           |
|fixed  |meetings_count_within                                |   0.0291|    0.0447|    0.6508| 1573.0|0.5153  |  -0.0586|    0.1168|Model 3: L1 Within-Person           |
|fixed  |meetings_mins_within                                 |   0.0008|    0.0009|    0.8181| 1573.0|0.4134  |  -0.0011|    0.0026|Model 3: L1 Within-Person           |
|fixed  |(Intercept)                                          |   0.4348|    0.1101|    3.9500|  817.6|< .001  |   0.2187|    0.6508|Model 4: L1 Within + Between        |
|fixed  |time_c                                               |  -0.0086|    0.0164|   -0.5238| 1573.0|0.6005  |  -0.0407|    0.0235|Model 4: L1 Within + Between        |
|fixed  |pf_mean_within                                       |   0.1043|    0.0295|    3.5351| 1573.0|< .001  |   0.0464|    0.1622|Model 4: L1 Within + Between        |
|fixed  |cw_mean_within                                       |   0.0801|    0.0317|    2.5217| 1573.0|0.0118  |   0.0178|    0.1423|Model 4: L1 Within + Between        |
|fixed  |ee_mean_within                                       |   0.0710|    0.0273|    2.5995| 1573.0|0.0094  |   0.0174|    0.1246|Model 4: L1 Within + Between        |
|fixed  |comp_mean_within                                     |   0.0589|    0.0286|    2.0623| 1573.0|0.0393  |   0.0029|    0.1150|Model 4: L1 Within + Between        |
|fixed  |auto_mean_within                                     |   0.0194|    0.0286|    0.6800| 1573.0|0.4966  |  -0.0366|    0.0755|Model 4: L1 Within + Between        |
|fixed  |relt_mean_within                                     |   0.0583|    0.0296|    1.9700| 1573.0|0.049   |   0.0003|    0.1163|Model 4: L1 Within + Between        |
|fixed  |meetings_count_within                                |   0.0291|    0.0447|    0.6508| 1573.0|0.5153  |  -0.0586|    0.1168|Model 4: L1 Within + Between        |
|fixed  |meetings_mins_within                                 |   0.0008|    0.0009|    0.8181| 1573.0|0.4134  |  -0.0011|    0.0026|Model 4: L1 Within + Between        |
|fixed  |pf_mean_between                                      |   0.1770|    0.0510|    3.4711|  782.0|< .001  |   0.0769|    0.2771|Model 4: L1 Within + Between        |
|fixed  |cw_mean_between                                      |   0.1528|    0.0545|    2.8018|  782.0|0.0052  |   0.0458|    0.2599|Model 4: L1 Within + Between        |
|fixed  |ee_mean_between                                      |   0.0671|    0.0478|    1.4049|  782.0|0.1604  |  -0.0267|    0.1609|Model 4: L1 Within + Between        |
|fixed  |comp_mean_between                                    |   0.0331|    0.0514|    0.6438|  782.0|0.5199  |  -0.0679|    0.1341|Model 4: L1 Within + Between        |
|fixed  |auto_mean_between                                    |   0.1041|    0.0544|    1.9149|  782.0|0.0559  |  -0.0026|    0.2109|Model 4: L1 Within + Between        |
|fixed  |relt_mean_between                                    |   0.1204|    0.0583|    2.0663|  782.0|0.0391  |   0.0060|    0.2348|Model 4: L1 Within + Between        |
|fixed  |meetings_count_between                               |  -0.0741|    0.0649|   -1.1423|  782.0|0.2537  |  -0.2015|    0.0532|Model 4: L1 Within + Between        |
|fixed  |meetings_mins_between                                |   0.0028|    0.0013|    2.0864|  782.0|0.0373  |   0.0002|    0.0054|Model 4: L1 Within + Between        |
|fixed  |(Intercept)                                          |   0.4217|    0.1106|    3.8133|  812.0|< .001  |   0.2046|    0.6387|Model 5: L1 + L2 Study Variables    |
|fixed  |time_c                                               |  -0.0086|    0.0164|   -0.5238| 1573.0|0.6005  |  -0.0407|    0.0235|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_within                                       |   0.1043|    0.0295|    3.5351| 1573.0|< .001  |   0.0464|    0.1622|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_within                                       |   0.0801|    0.0317|    2.5217| 1573.0|0.0118  |   0.0178|    0.1423|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_within                                       |   0.0710|    0.0273|    2.5995| 1573.0|0.0094  |   0.0174|    0.1246|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_within                                     |   0.0589|    0.0286|    2.0623| 1573.0|0.0393  |   0.0029|    0.1150|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_within                                     |   0.0194|    0.0286|    0.6800| 1573.0|0.4966  |  -0.0366|    0.0755|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_within                                     |   0.0583|    0.0296|    1.9700| 1573.0|0.049   |   0.0003|    0.1163|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_within                                |   0.0291|    0.0447|    0.6508| 1573.0|0.5153  |  -0.0586|    0.1168|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_mins_within                                 |   0.0008|    0.0009|    0.8181| 1573.0|0.4134  |  -0.0011|    0.0026|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_between                                      |   0.1760|    0.0511|    3.4473|  777.0|< .001  |   0.0758|    0.2763|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_between                                      |   0.1534|    0.0547|    2.8068|  777.0|0.0051  |   0.0461|    0.2607|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_between                                      |   0.0664|    0.0479|    1.3864|  777.0|0.166   |  -0.0276|    0.1603|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_between                                    |   0.0327|    0.0515|    0.6352|  777.0|0.5255  |  -0.0684|    0.1339|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_between                                    |   0.1068|    0.0545|    1.9608|  777.0|0.0503  |  -0.0001|    0.2137|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_between                                    |   0.1212|    0.0584|    2.0762|  777.0|0.0382  |   0.0066|    0.2357|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_between                               |  -0.0645|    0.0653|   -0.9885|  777.0|0.3232  |  -0.1927|    0.0636|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_mins_between                                |   0.0026|    0.0013|    1.9562|  777.0|0.0508  |   0.0000|    0.0052|Model 5: L1 + L2 Study Variables    |
|fixed  |pa_mean_c                                            |  -0.0245|    0.0346|   -0.7105|  777.0|0.4776  |  -0.0924|    0.0433|Model 5: L1 + L2 Study Variables    |
|fixed  |na_mean_c                                            |  -0.0001|    0.0331|   -0.0036|  777.0|0.9971  |  -0.0651|    0.0649|Model 5: L1 + L2 Study Variables    |
|fixed  |br_mean_c                                            |   0.0254|    0.0450|    0.5633|  777.0|0.5734  |  -0.0630|    0.1138|Model 5: L1 + L2 Study Variables    |
|fixed  |vio_mean_c                                           |   0.0018|    0.0400|    0.0458|  777.0|0.9635  |  -0.0768|    0.0804|Model 5: L1 + L2 Study Variables    |
|fixed  |js_mean_c                                            |   0.0583|    0.0305|    1.9136|  777.0|0.056   |  -0.0015|    0.1181|Model 5: L1 + L2 Study Variables    |
|fixed  |(Intercept)                                          |   0.4801|    0.3255|    1.4751|  761.9|0.1406  |  -0.1588|    1.1191|Model 6: Full Model with Covariates |
|fixed  |time_c                                               |  -0.0086|    0.0164|   -0.5238| 1573.0|0.6005  |  -0.0407|    0.0235|Model 6: Full Model with Covariates |
|fixed  |pf_mean_within                                       |   0.1043|    0.0295|    3.5351| 1573.0|< .001  |   0.0464|    0.1622|Model 6: Full Model with Covariates |
|fixed  |cw_mean_within                                       |   0.0801|    0.0317|    2.5217| 1573.0|0.0118  |   0.0178|    0.1423|Model 6: Full Model with Covariates |
|fixed  |ee_mean_within                                       |   0.0710|    0.0273|    2.5995| 1573.0|0.0094  |   0.0174|    0.1246|Model 6: Full Model with Covariates |
|fixed  |comp_mean_within                                     |   0.0589|    0.0286|    2.0623| 1573.0|0.0393  |   0.0029|    0.1150|Model 6: Full Model with Covariates |
|fixed  |auto_mean_within                                     |   0.0194|    0.0286|    0.6800| 1573.0|0.4966  |  -0.0366|    0.0755|Model 6: Full Model with Covariates |
|fixed  |relt_mean_within                                     |   0.0583|    0.0296|    1.9700| 1573.0|0.049   |   0.0003|    0.1163|Model 6: Full Model with Covariates |
|fixed  |meetings_count_within                                |   0.0291|    0.0447|    0.6508| 1573.0|0.5153  |  -0.0586|    0.1168|Model 6: Full Model with Covariates |
|fixed  |meetings_mins_within                                 |   0.0008|    0.0009|    0.8181| 1573.0|0.4134  |  -0.0011|    0.0026|Model 6: Full Model with Covariates |
|fixed  |pf_mean_between                                      |   0.1936|    0.0521|    3.7178|  758.0|< .001  |   0.0914|    0.2958|Model 6: Full Model with Covariates |
|fixed  |cw_mean_between                                      |   0.1461|    0.0549|    2.6604|  758.0|0.008   |   0.0383|    0.2539|Model 6: Full Model with Covariates |
|fixed  |ee_mean_between                                      |   0.0578|    0.0482|    1.1999|  758.0|0.2305  |  -0.0368|    0.1525|Model 6: Full Model with Covariates |
|fixed  |comp_mean_between                                    |   0.0272|    0.0525|    0.5189|  758.0|0.604   |  -0.0758|    0.1302|Model 6: Full Model with Covariates |
|fixed  |auto_mean_between                                    |   0.1034|    0.0551|    1.8749|  758.0|0.0612  |  -0.0049|    0.2116|Model 6: Full Model with Covariates |
|fixed  |relt_mean_between                                    |   0.1200|    0.0588|    2.0412|  758.0|0.0416  |   0.0046|    0.2353|Model 6: Full Model with Covariates |
|fixed  |meetings_count_between                               |  -0.0777|    0.0655|   -1.1859|  758.0|0.236   |  -0.2063|    0.0509|Model 6: Full Model with Covariates |
|fixed  |meetings_mins_between                                |   0.0030|    0.0013|    2.2620|  758.0|0.024   |   0.0004|    0.0056|Model 6: Full Model with Covariates |
|fixed  |pa_mean_c                                            |  -0.0288|    0.0349|   -0.8255|  758.0|0.4093  |  -0.0972|    0.0397|Model 6: Full Model with Covariates |
|fixed  |na_mean_c                                            |  -0.0074|    0.0337|   -0.2198|  758.0|0.8261  |  -0.0736|    0.0588|Model 6: Full Model with Covariates |
|fixed  |br_mean_c                                            |   0.0257|    0.0455|    0.5645|  758.0|0.5726  |  -0.0636|    0.1149|Model 6: Full Model with Covariates |
|fixed  |vio_mean_c                                           |   0.0006|    0.0404|    0.0150|  758.0|0.988   |  -0.0787|    0.0799|Model 6: Full Model with Covariates |
|fixed  |js_mean_c                                            |   0.0660|    0.0306|    2.1569|  758.0|0.0313  |   0.0059|    0.1260|Model 6: Full Model with Covariates |
|fixed  |age_c                                                |   0.0046|    0.0024|    1.8749|  758.0|0.0612  |  -0.0002|    0.0094|Model 6: Full Model with Covariates |
|fixed  |job_tenure3 to 5 years                               |   0.0567|    0.0614|    0.9237|  758.0|0.356   |  -0.0638|    0.1773|Model 6: Full Model with Covariates |
|fixed  |job_tenureLess than a year                           |  -0.0240|    0.0734|   -0.3262|  758.0|0.7444  |  -0.1681|    0.1202|Model 6: Full Model with Covariates |
|fixed  |job_tenureMore than 5 years                          |  -0.0275|    0.0609|   -0.4525|  758.0|0.651   |  -0.1470|    0.0919|Model 6: Full Model with Covariates |
|fixed  |edu_lvlBachelor's degree                             |  -0.1084|    0.0905|   -1.1978|  758.0|0.2314  |  -0.2862|    0.0693|Model 6: Full Model with Covariates |
|fixed  |edu_lvlHigh school diploma or equivalent (e.g., GED) |  -0.2028|    0.1068|   -1.8984|  758.0|0.058   |  -0.4126|    0.0069|Model 6: Full Model with Covariates |
|fixed  |edu_lvlMaster's degree                               |  -0.1489|    0.1031|   -1.4445|  758.0|0.149   |  -0.3513|    0.0535|Model 6: Full Model with Covariates |
|fixed  |edu_lvlProfessional or doctorate degree              |  -0.2489|    0.1184|   -2.1025|  758.0|0.0358  |  -0.4813|   -0.0165|Model 6: Full Model with Covariates |
|fixed  |edu_lvlSome college, no degree                       |  -0.0834|    0.0998|   -0.8355|  758.0|0.4037  |  -0.2793|    0.1125|Model 6: Full Model with Covariates |
|fixed  |edu_lvlSome high school, no diploma                  |  -0.0207|    0.2456|   -0.0843|  758.0|0.9329  |  -0.5028|    0.4614|Model 6: Full Model with Covariates |
|fixed  |edu_lvlVocational training                           |  -0.1762|    0.1251|   -1.4082|  758.0|0.1595  |  -0.4218|    0.0694|Model 6: Full Model with Covariates |
|fixed  |ethnicityArab, Middle Eastern, or North African      |  -0.1844|    0.3253|   -0.5670|  758.0|0.5709  |  -0.8229|    0.4541|Model 6: Full Model with Covariates |
|fixed  |ethnicityAsian                                       |   0.1637|    0.2990|    0.5475|  758.0|0.5842  |  -0.4233|    0.7507|Model 6: Full Model with Covariates |
|fixed  |ethnicityBlack or African American                   |   0.1773|    0.2976|    0.5959|  758.0|0.5514  |  -0.4069|    0.7616|Model 6: Full Model with Covariates |
|fixed  |ethnicityHispanic or Latino                          |   0.0615|    0.2955|    0.2082|  758.0|0.8352  |  -0.5186|    0.6417|Model 6: Full Model with Covariates |
|fixed  |ethnicityNative Hawaiian or other Pacific Islander   |   0.4022|    0.4339|    0.9269|  758.0|0.3543  |  -0.4496|    1.2539|Model 6: Full Model with Covariates |
|fixed  |ethnicityPrefer not to say                           |  -0.1036|    0.3402|   -0.3046|  758.0|0.7608  |  -0.7715|    0.5643|Model 6: Full Model with Covariates |
|fixed  |ethnicityTwo or more races                           |   0.1577|    0.3072|    0.5132|  758.0|0.608   |  -0.4454|    0.7607|Model 6: Full Model with Covariates |
|fixed  |ethnicityWhite or Caucasian                          |   0.0423|    0.2919|    0.1450|  758.0|0.8848  |  -0.5308|    0.6154|Model 6: Full Model with Covariates |
