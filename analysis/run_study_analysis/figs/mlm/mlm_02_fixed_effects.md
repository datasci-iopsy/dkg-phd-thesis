|effect |term                                                 | estimate| std.error| statistic|    df|p.value | conf.low| conf.high|model                               |
|:------|:----------------------------------------------------|--------:|---------:|---------:|-----:|:-------|--------:|---------:|:-----------------------------------|
|fixed  |(Intercept)                                          |   1.5797|    0.0577|   27.3825| 321.0|< .001  |   1.4662|    1.6932|Model 0: Unconditional Means        |
|fixed  |(Intercept)                                          |   1.5176|    0.0609|   24.9257| 395.7|< .001  |   1.3979|    1.6373|Model 1: Fixed Time                 |
|fixed  |time_c                                               |   0.0621|    0.0195|    3.1914| 643.0|0.0015  |   0.0239|    0.1003|Model 1: Fixed Time                 |
|fixed  |(Intercept)                                          |   1.5176|    0.0570|   26.6193| 321.0|< .001  |   1.4054|    1.6298|Model 2: Random Slope               |
|fixed  |time_c                                               |   0.0621|    0.0208|    2.9848| 321.0|0.0031  |   0.0212|    0.1031|Model 2: Random Slope               |
|fixed  |(Intercept)                                          |   1.4383|    0.0655|   21.9587| 325.8|< .001  |   1.3095|    1.5672|Model 3: L1 Within-Person           |
|fixed  |time_c                                               |   0.0428|    0.0191|    2.2443| 329.3|0.0255  |   0.0053|    0.0803|Model 3: L1 Within-Person           |
|fixed  |pf_mean_within                                       |   0.1804|    0.0435|    4.1478| 631.6|< .001  |   0.0950|    0.2658|Model 3: L1 Within-Person           |
|fixed  |cw_mean_within                                       |   0.0084|    0.0403|    0.2094| 629.7|0.8342  |  -0.0707|    0.0876|Model 3: L1 Within-Person           |
|fixed  |ee_mean_within                                       |   0.2184|    0.0425|    5.1355| 591.4|< .001  |   0.1349|    0.3019|Model 3: L1 Within-Person           |
|fixed  |comp_mean_within                                     |   0.1381|    0.0468|    2.9530| 634.9|0.0033  |   0.0463|    0.2300|Model 3: L1 Within-Person           |
|fixed  |auto_mean_within                                     |  -0.0083|    0.0338|   -0.2462| 620.3|0.8056  |  -0.0748|    0.0581|Model 3: L1 Within-Person           |
|fixed  |relt_mean_within                                     |   0.0061|    0.0480|    0.1263| 623.4|0.8995  |  -0.0882|    0.1003|Model 3: L1 Within-Person           |
|fixed  |meetings_count_within                                |  -0.0132|    0.0291|   -0.4521| 599.0|0.6514  |  -0.0704|    0.0441|Model 3: L1 Within-Person           |
|fixed  |meetings_time_within                                 |   0.0006|    0.0008|    0.6860| 585.5|0.493   |  -0.0010|    0.0022|Model 3: L1 Within-Person           |
|fixed  |recruitment_sourcesnowball                           |   0.4122|    0.1320|    3.1239| 320.0|0.0019  |   0.1526|    0.6718|Model 3: L1 Within-Person           |
|fixed  |(Intercept)                                          |  -0.4239|    0.1223|   -3.4674| 319.6|< .001  |  -0.6644|   -0.1834|Model 4: L1 Within + Between        |
|fixed  |time_c                                               |   0.0419|    0.0191|    2.1999| 330.0|0.0285  |   0.0044|    0.0794|Model 4: L1 Within + Between        |
|fixed  |pf_mean_within                                       |   0.1857|    0.0436|    4.2623| 631.9|< .001  |   0.1001|    0.2712|Model 4: L1 Within + Between        |
|fixed  |cw_mean_within                                       |   0.0048|    0.0404|    0.1185| 629.8|0.9057  |  -0.0745|    0.0841|Model 4: L1 Within + Between        |
|fixed  |ee_mean_within                                       |   0.2256|    0.0426|    5.2971| 591.8|< .001  |   0.1420|    0.3093|Model 4: L1 Within + Between        |
|fixed  |comp_mean_within                                     |   0.1454|    0.0469|    3.1037| 635.3|0.002   |   0.0534|    0.2374|Model 4: L1 Within + Between        |
|fixed  |auto_mean_within                                     |  -0.0041|    0.0339|   -0.1210| 620.9|0.9038  |  -0.0707|    0.0625|Model 4: L1 Within + Between        |
|fixed  |relt_mean_within                                     |  -0.0048|    0.0481|   -0.0992| 624.1|0.921   |  -0.0992|    0.0896|Model 4: L1 Within + Between        |
|fixed  |meetings_count_within                                |  -0.0161|    0.0292|   -0.5507| 598.6|0.582   |  -0.0734|    0.0412|Model 4: L1 Within + Between        |
|fixed  |meetings_time_within                                 |   0.0006|    0.0008|    0.7307| 585.1|0.4652  |  -0.0010|    0.0022|Model 4: L1 Within + Between        |
|fixed  |pf_mean_between                                      |   0.5203|    0.0811|    6.4181| 312.0|< .001  |   0.3608|    0.6799|Model 4: L1 Within + Between        |
|fixed  |cw_mean_between                                      |  -0.2273|    0.0742|   -3.0636| 312.0|0.0024  |  -0.3732|   -0.0813|Model 4: L1 Within + Between        |
|fixed  |ee_mean_between                                      |   0.5435|    0.0921|    5.9013| 311.9|< .001  |   0.3623|    0.7247|Model 4: L1 Within + Between        |
|fixed  |comp_mean_between                                    |   0.0935|    0.0832|    1.1239| 312.0|0.2619  |  -0.0702|    0.2571|Model 4: L1 Within + Between        |
|fixed  |auto_mean_between                                    |   0.0418|    0.0558|    0.7506| 312.2|0.4535  |  -0.0679|    0.1515|Model 4: L1 Within + Between        |
|fixed  |relt_mean_between                                    |   0.1066|    0.0980|    1.0874| 312.1|0.2777  |  -0.0863|    0.2994|Model 4: L1 Within + Between        |
|fixed  |meetings_count_between                               |   0.3201|    0.0813|    3.9399| 312.3|< .001  |   0.1603|    0.4800|Model 4: L1 Within + Between        |
|fixed  |meetings_time_between                                |  -0.0078|    0.0020|   -3.9701| 312.0|< .001  |  -0.0116|   -0.0039|Model 4: L1 Within + Between        |
|fixed  |recruitment_sourcesnowball                           |   0.4461|    0.0948|    4.7074| 312.1|< .001  |   0.2596|    0.6326|Model 4: L1 Within + Between        |
|fixed  |(Intercept)                                          |   0.0688|    0.1374|    0.5007| 314.4|0.6169  |  -0.2015|    0.3391|Model 5: L1 + L2 Study Variables    |
|fixed  |time_c                                               |   0.0415|    0.0191|    2.1794| 330.1|0.03    |   0.0040|    0.0790|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_within                                       |   0.1920|    0.0436|    4.4020| 632.1|< .001  |   0.1063|    0.2776|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_within                                       |   0.0033|    0.0404|    0.0820| 629.7|0.9347  |  -0.0760|    0.0827|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_within                                       |   0.2263|    0.0426|    5.3067| 592.1|< .001  |   0.1426|    0.3101|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_within                                     |   0.1427|    0.0469|    3.0424| 634.9|0.0024  |   0.0506|    0.2348|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_within                                     |  -0.0055|    0.0339|   -0.1607| 620.7|0.8724  |  -0.0721|    0.0612|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_within                                     |  -0.0008|    0.0481|   -0.0156| 624.0|0.9875  |  -0.0953|    0.0937|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_within                                |  -0.0147|    0.0292|   -0.5046| 598.1|0.614   |  -0.0721|    0.0426|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_time_within                                 |   0.0006|    0.0008|    0.7214| 584.5|0.4709  |  -0.0010|    0.0022|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_between                                      |   0.4195|    0.0742|    5.6513| 307.0|< .001  |   0.2734|    0.5656|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_between                                      |  -0.1162|    0.0687|   -1.6908| 307.0|0.0919  |  -0.2515|    0.0190|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_between                                      |   0.3901|    0.0853|    4.5709| 306.9|< .001  |   0.2222|    0.5580|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_between                                    |   0.0632|    0.0765|    0.8265| 307.0|0.4092  |  -0.0873|    0.2138|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_between                                    |   0.0046|    0.0508|    0.0901| 307.1|0.9283  |  -0.0953|    0.1045|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_between                                    |   0.0249|    0.0899|    0.2764| 307.0|0.7824  |  -0.1521|    0.2018|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_between                               |   0.3202|    0.0731|    4.3821| 307.2|< .001  |   0.1764|    0.4640|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_time_between                                |  -0.0067|    0.0018|   -3.7652| 307.0|< .001  |  -0.0103|   -0.0032|Model 5: L1 + L2 Study Variables    |
|fixed  |pa_mean_c                                            |   0.0826|    0.0691|    1.1952| 307.0|0.2329  |  -0.0534|    0.2185|Model 5: L1 + L2 Study Variables    |
|fixed  |na_mean_c                                            |  -0.0128|    0.0731|   -0.1756| 306.9|0.8607  |  -0.1568|    0.1311|Model 5: L1 + L2 Study Variables    |
|fixed  |br_mean_c                                            |   0.1313|    0.0664|    1.9771| 306.9|0.0489  |   0.0006|    0.2620|Model 5: L1 + L2 Study Variables    |
|fixed  |vio_mean_c                                           |   0.0919|    0.0743|    1.2367| 307.0|0.2172  |  -0.0543|    0.2382|Model 5: L1 + L2 Study Variables    |
|fixed  |js_mean_c                                            |  -0.1783|    0.0439|   -4.0623| 307.2|< .001  |  -0.2646|   -0.0919|Model 5: L1 + L2 Study Variables    |
|fixed  |recruitment_sourcesnowball                           |   0.2720|    0.0883|    3.0787| 307.0|0.0023  |   0.0981|    0.4458|Model 5: L1 + L2 Study Variables    |
|fixed  |(Intercept)                                          |   0.0352|    0.2005|    0.1757| 300.3|0.8606  |  -0.3593|    0.4298|Model 6: Full Model with Covariates |
|fixed  |time_c                                               |   0.0415|    0.0191|    2.1789| 330.1|0.03    |   0.0040|    0.0790|Model 6: Full Model with Covariates |
|fixed  |pf_mean_within                                       |   0.1925|    0.0436|    4.4152| 631.8|< .001  |   0.1069|    0.2782|Model 6: Full Model with Covariates |
|fixed  |cw_mean_within                                       |   0.0027|    0.0404|    0.0657| 629.2|0.9476  |  -0.0767|    0.0820|Model 6: Full Model with Covariates |
|fixed  |ee_mean_within                                       |   0.2262|    0.0426|    5.3043| 591.7|< .001  |   0.1424|    0.3099|Model 6: Full Model with Covariates |
|fixed  |comp_mean_within                                     |   0.1427|    0.0469|    3.0424| 634.7|0.0024  |   0.0506|    0.2347|Model 6: Full Model with Covariates |
|fixed  |auto_mean_within                                     |  -0.0053|    0.0339|   -0.1563| 620.3|0.8758  |  -0.0719|    0.0613|Model 6: Full Model with Covariates |
|fixed  |relt_mean_within                                     |  -0.0010|    0.0481|   -0.0208| 623.8|0.9834  |  -0.0955|    0.0935|Model 6: Full Model with Covariates |
|fixed  |meetings_count_within                                |  -0.0147|    0.0292|   -0.5044| 598.0|0.6142  |  -0.0721|    0.0426|Model 6: Full Model with Covariates |
|fixed  |meetings_time_within                                 |   0.0006|    0.0008|    0.7147| 584.4|0.4751  |  -0.0010|    0.0022|Model 6: Full Model with Covariates |
|fixed  |pf_mean_between                                      |   0.4217|    0.0769|    5.4822| 297.0|< .001  |   0.2703|    0.5731|Model 6: Full Model with Covariates |
|fixed  |cw_mean_between                                      |  -0.1182|    0.0704|   -1.6781| 297.0|0.0944  |  -0.2568|    0.0204|Model 6: Full Model with Covariates |
|fixed  |ee_mean_between                                      |   0.3981|    0.0876|    4.5462| 297.0|< .001  |   0.2258|    0.5704|Model 6: Full Model with Covariates |
|fixed  |comp_mean_between                                    |   0.0529|    0.0778|    0.6802| 297.0|0.4969  |  -0.1002|    0.2060|Model 6: Full Model with Covariates |
|fixed  |auto_mean_between                                    |  -0.0028|    0.0520|   -0.0541| 297.1|0.9569  |  -0.1051|    0.0995|Model 6: Full Model with Covariates |
|fixed  |relt_mean_between                                    |   0.0302|    0.0913|    0.3305| 297.0|0.7412  |  -0.1494|    0.2097|Model 6: Full Model with Covariates |
|fixed  |meetings_count_between                               |   0.3338|    0.0741|    4.5033| 297.2|< .001  |   0.1879|    0.4796|Model 6: Full Model with Covariates |
|fixed  |meetings_time_between                                |  -0.0073|    0.0018|   -3.9594| 297.0|< .001  |  -0.0109|   -0.0037|Model 6: Full Model with Covariates |
|fixed  |pa_mean_c                                            |   0.0734|    0.0705|    1.0414| 297.0|0.2985  |  -0.0653|    0.2120|Model 6: Full Model with Covariates |
|fixed  |na_mean_c                                            |   0.0057|    0.0753|    0.0761| 296.9|0.9394  |  -0.1425|    0.1540|Model 6: Full Model with Covariates |
|fixed  |br_mean_c                                            |   0.1456|    0.0684|    2.1303| 296.9|0.034   |   0.0111|    0.2801|Model 6: Full Model with Covariates |
|fixed  |vio_mean_c                                           |   0.0896|    0.0756|    1.1853| 297.0|0.2368  |  -0.0591|    0.2383|Model 6: Full Model with Covariates |
|fixed  |js_mean_c                                            |  -0.1646|    0.0453|   -3.6369| 297.1|< .001  |  -0.2537|   -0.0755|Model 6: Full Model with Covariates |
|fixed  |recruitment_sourcesnowball                           |   0.2244|    0.1029|    2.1810| 297.0|0.03    |   0.0219|    0.4270|Model 6: Full Model with Covariates |
|fixed  |age_c                                                |   0.0027|    0.0039|    0.6936| 297.0|0.4885  |  -0.0050|    0.0104|Model 6: Full Model with Covariates |
|fixed  |job_tenure3 to 5 years                               |  -0.0754|    0.1111|   -0.6786| 297.0|0.4979  |  -0.2940|    0.1433|Model 6: Full Model with Covariates |
|fixed  |job_tenureLess than a year                           |   0.0476|    0.1348|    0.3532| 296.9|0.7242  |  -0.2177|    0.3130|Model 6: Full Model with Covariates |
|fixed  |job_tenureMore than 5 years                          |  -0.0145|    0.1004|   -0.1442| 297.0|0.8855  |  -0.2122|    0.1832|Model 6: Full Model with Covariates |
|fixed  |edu_lvlBachelor's degree                             |   0.0340|    0.1347|    0.2524| 296.9|0.8009  |  -0.2312|    0.2992|Model 6: Full Model with Covariates |
|fixed  |edu_lvlHigh school diploma or equivalent (e.g., GED) |   0.0717|    0.1927|    0.3722| 296.9|0.71    |  -0.3075|    0.4510|Model 6: Full Model with Covariates |
|fixed  |edu_lvlMaster's degree                               |   0.2184|    0.1509|    1.4478| 296.9|0.1487  |  -0.0785|    0.5153|Model 6: Full Model with Covariates |
|fixed  |edu_lvlProfessional or doctorate degree              |   0.0854|    0.1711|    0.4993| 297.0|0.618   |  -0.2512|    0.4220|Model 6: Full Model with Covariates |
|fixed  |edu_lvlSome college, no degree                       |   0.0610|    0.1568|    0.3890| 297.0|0.6975  |  -0.2476|    0.3697|Model 6: Full Model with Covariates |
|fixed  |edu_lvlVocational training                           |   0.2905|    0.3852|    0.7541| 296.9|0.4514  |  -0.4676|    1.0485|Model 6: Full Model with Covariates |
