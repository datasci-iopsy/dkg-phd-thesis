|effect |term                                               | estimate| std.error| statistic|     df|p.value | conf.low| conf.high|model                               |
|:------|:--------------------------------------------------|--------:|---------:|---------:|------:|:-------|--------:|---------:|:-----------------------------------|
|fixed  |(Intercept)                                        |   1.9158|    0.0262|   73.2564|  771.0|< .001  |   1.8645|    1.9671|Model 0: Unconditional Means        |
|fixed  |(Intercept)                                        |   1.9216|    0.0314|   61.1500| 1463.3|< .001  |   1.8600|    1.9833|Model 1: Fixed Time                 |
|fixed  |time_c                                             |  -0.0058|    0.0174|   -0.3345| 1543.0|0.738   |  -0.0400|    0.0283|Model 1: Fixed Time                 |
|fixed  |(Intercept)                                        |   1.9216|    0.0321|   59.8110|  771.0|< .001  |   1.8586|    1.9847|Model 2: Random Slope               |
|fixed  |time_c                                             |  -0.0058|    0.0175|   -0.3322|  771.0|0.7398  |  -0.0403|    0.0286|Model 2: Random Slope               |
|fixed  |(Intercept)                                        |   1.9250|    0.0310|   62.1559| 1402.3|< .001  |   1.8642|    1.9857|Model 3: L1 Within-Person           |
|fixed  |time_c                                             |  -0.0092|    0.0166|   -0.5525| 1535.0|0.5807  |  -0.0417|    0.0234|Model 3: L1 Within-Person           |
|fixed  |pf_mean_within                                     |   0.1040|    0.0298|    3.4928| 1535.0|< .001  |   0.0456|    0.1625|Model 3: L1 Within-Person           |
|fixed  |cw_mean_within                                     |   0.0842|    0.0322|    2.6180| 1535.0|0.0089  |   0.0211|    0.1472|Model 3: L1 Within-Person           |
|fixed  |ee_mean_within                                     |   0.0667|    0.0276|    2.4185| 1535.0|0.0157  |   0.0126|    0.1207|Model 3: L1 Within-Person           |
|fixed  |comp_mean_within                                   |   0.0545|    0.0288|    1.8906| 1535.0|0.0589  |  -0.0020|    0.1110|Model 3: L1 Within-Person           |
|fixed  |auto_mean_within                                   |   0.0205|    0.0288|    0.7119| 1535.0|0.4766  |  -0.0360|    0.0769|Model 3: L1 Within-Person           |
|fixed  |relt_mean_within                                   |   0.0557|    0.0298|    1.8671| 1535.0|0.0621  |  -0.0028|    0.1142|Model 3: L1 Within-Person           |
|fixed  |meetings_count_within                              |   0.0202|    0.0451|    0.4484| 1535.0|0.6539  |  -0.0683|    0.1087|Model 3: L1 Within-Person           |
|fixed  |meetings_mins_within                               |   0.0009|    0.0009|    0.9274| 1535.0|0.3539  |  -0.0010|    0.0027|Model 3: L1 Within-Person           |
|fixed  |(Intercept)                                        |   0.4201|    0.1145|    3.6689|  795.9|< .001  |   0.1953|    0.6449|Model 4: L1 Within + Between        |
|fixed  |time_c                                             |  -0.0092|    0.0166|   -0.5525| 1535.0|0.5807  |  -0.0417|    0.0234|Model 4: L1 Within + Between        |
|fixed  |pf_mean_within                                     |   0.1040|    0.0298|    3.4928| 1535.0|< .001  |   0.0456|    0.1625|Model 4: L1 Within + Between        |
|fixed  |cw_mean_within                                     |   0.0842|    0.0322|    2.6180| 1535.0|0.0089  |   0.0211|    0.1472|Model 4: L1 Within + Between        |
|fixed  |ee_mean_within                                     |   0.0667|    0.0276|    2.4185| 1535.0|0.0157  |   0.0126|    0.1207|Model 4: L1 Within + Between        |
|fixed  |comp_mean_within                                   |   0.0545|    0.0288|    1.8906| 1535.0|0.0589  |  -0.0020|    0.1110|Model 4: L1 Within + Between        |
|fixed  |auto_mean_within                                   |   0.0205|    0.0288|    0.7119| 1535.0|0.4766  |  -0.0360|    0.0769|Model 4: L1 Within + Between        |
|fixed  |relt_mean_within                                   |   0.0557|    0.0298|    1.8671| 1535.0|0.0621  |  -0.0028|    0.1142|Model 4: L1 Within + Between        |
|fixed  |meetings_count_within                              |   0.0202|    0.0451|    0.4484| 1535.0|0.6539  |  -0.0683|    0.1087|Model 4: L1 Within + Between        |
|fixed  |meetings_mins_within                               |   0.0009|    0.0009|    0.9274| 1535.0|0.3539  |  -0.0010|    0.0027|Model 4: L1 Within + Between        |
|fixed  |pf_mean_between                                    |   0.1883|    0.0514|    3.6611|  763.0|< .001  |   0.0873|    0.2892|Model 4: L1 Within + Between        |
|fixed  |cw_mean_between                                    |   0.1506|    0.0547|    2.7539|  763.0|0.006   |   0.0433|    0.2580|Model 4: L1 Within + Between        |
|fixed  |ee_mean_between                                    |   0.0641|    0.0482|    1.3315|  763.0|0.1834  |  -0.0304|    0.1587|Model 4: L1 Within + Between        |
|fixed  |comp_mean_between                                  |   0.0368|    0.0518|    0.7097|  763.0|0.4781  |  -0.0650|    0.1386|Model 4: L1 Within + Between        |
|fixed  |auto_mean_between                                  |   0.0968|    0.0548|    1.7652|  763.0|0.0779  |  -0.0108|    0.2044|Model 4: L1 Within + Between        |
|fixed  |relt_mean_between                                  |   0.1209|    0.0586|    2.0629|  763.0|0.0395  |   0.0059|    0.2360|Model 4: L1 Within + Between        |
|fixed  |meetings_count_between                             |  -0.0725|    0.0657|   -1.1039|  763.0|0.27    |  -0.2015|    0.0564|Model 4: L1 Within + Between        |
|fixed  |meetings_mins_between                              |   0.0028|    0.0013|    2.0945|  763.0|0.0365  |   0.0002|    0.0054|Model 4: L1 Within + Between        |
|fixed  |(Intercept)                                        |   0.4071|    0.1150|    3.5384|  790.4|< .001  |   0.1812|    0.6329|Model 5: L1 + L2 Study Variables    |
|fixed  |time_c                                             |  -0.0092|    0.0166|   -0.5525| 1535.0|0.5807  |  -0.0417|    0.0234|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_within                                     |   0.1040|    0.0298|    3.4928| 1535.0|< .001  |   0.0456|    0.1625|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_within                                     |   0.0842|    0.0322|    2.6180| 1535.0|0.0089  |   0.0211|    0.1472|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_within                                     |   0.0667|    0.0276|    2.4185| 1535.0|0.0157  |   0.0126|    0.1207|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_within                                   |   0.0545|    0.0288|    1.8906| 1535.0|0.0589  |  -0.0020|    0.1110|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_within                                   |   0.0205|    0.0288|    0.7119| 1535.0|0.4766  |  -0.0360|    0.0769|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_within                                   |   0.0557|    0.0298|    1.8671| 1535.0|0.0621  |  -0.0028|    0.1142|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_within                              |   0.0202|    0.0451|    0.4484| 1535.0|0.6539  |  -0.0683|    0.1087|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_mins_within                               |   0.0009|    0.0009|    0.9274| 1535.0|0.3539  |  -0.0010|    0.0027|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_between                                    |   0.1881|    0.0515|    3.6525|  758.0|< .001  |   0.0870|    0.2892|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_between                                    |   0.1516|    0.0548|    2.7677|  758.0|0.0058  |   0.0441|    0.2591|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_between                                    |   0.0628|    0.0483|    1.3017|  758.0|0.1934  |  -0.0319|    0.1576|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_between                                  |   0.0364|    0.0520|    0.7005|  758.0|0.4838  |  -0.0656|    0.1384|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_between                                  |   0.0985|    0.0549|    1.7942|  758.0|0.0732  |  -0.0093|    0.2062|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_between                                  |   0.1225|    0.0587|    2.0864|  758.0|0.0373  |   0.0072|    0.2377|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_between                             |  -0.0642|    0.0661|   -0.9711|  758.0|0.3318  |  -0.1939|    0.0655|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_mins_between                              |   0.0027|    0.0013|    1.9822|  758.0|0.0478  |   0.0000|    0.0053|Model 5: L1 + L2 Study Variables    |
|fixed  |pa_mean_c                                          |  -0.0165|    0.0351|   -0.4713|  758.0|0.6376  |  -0.0854|    0.0523|Model 5: L1 + L2 Study Variables    |
|fixed  |na_mean_c                                          |   0.0046|    0.0333|    0.1385|  758.0|0.8899  |  -0.0608|    0.0700|Model 5: L1 + L2 Study Variables    |
|fixed  |br_mean_c                                          |   0.0172|    0.0456|    0.3777|  758.0|0.7057  |  -0.0723|    0.1067|Model 5: L1 + L2 Study Variables    |
|fixed  |vio_mean_c                                         |   0.0127|    0.0406|    0.3117|  758.0|0.7554  |  -0.0671|    0.0924|Model 5: L1 + L2 Study Variables    |
|fixed  |js_mean_c                                          |   0.0595|    0.0308|    1.9299|  758.0|0.054   |  -0.0010|    0.1201|Model 5: L1 + L2 Study Variables    |
|fixed  |(Intercept)                                        |   0.3164|    0.3154|    1.0034|  750.1|0.316   |  -0.3026|    0.9355|Model 6: Full Model with Covariates |
|fixed  |time_c                                             |  -0.0092|    0.0166|   -0.5525| 1535.0|0.5807  |  -0.0417|    0.0234|Model 6: Full Model with Covariates |
|fixed  |pf_mean_within                                     |   0.1040|    0.0298|    3.4928| 1535.0|< .001  |   0.0456|    0.1625|Model 6: Full Model with Covariates |
|fixed  |cw_mean_within                                     |   0.0842|    0.0322|    2.6180| 1535.0|0.0089  |   0.0211|    0.1472|Model 6: Full Model with Covariates |
|fixed  |ee_mean_within                                     |   0.0667|    0.0276|    2.4185| 1535.0|0.0157  |   0.0126|    0.1207|Model 6: Full Model with Covariates |
|fixed  |comp_mean_within                                   |   0.0545|    0.0288|    1.8906| 1535.0|0.0589  |  -0.0020|    0.1110|Model 6: Full Model with Covariates |
|fixed  |auto_mean_within                                   |   0.0205|    0.0288|    0.7119| 1535.0|0.4766  |  -0.0360|    0.0769|Model 6: Full Model with Covariates |
|fixed  |relt_mean_within                                   |   0.0557|    0.0298|    1.8671| 1535.0|0.0621  |  -0.0028|    0.1142|Model 6: Full Model with Covariates |
|fixed  |meetings_count_within                              |   0.0202|    0.0451|    0.4484| 1535.0|0.6539  |  -0.0683|    0.1087|Model 6: Full Model with Covariates |
|fixed  |meetings_mins_within                               |   0.0009|    0.0009|    0.9274| 1535.0|0.3539  |  -0.0010|    0.0027|Model 6: Full Model with Covariates |
|fixed  |pf_mean_between                                    |   0.1999|    0.0520|    3.8459|  746.0|< .001  |   0.0979|    0.3020|Model 6: Full Model with Covariates |
|fixed  |cw_mean_between                                    |   0.1446|    0.0549|    2.6318|  746.0|0.0087  |   0.0367|    0.2524|Model 6: Full Model with Covariates |
|fixed  |ee_mean_between                                    |   0.0541|    0.0485|    1.1162|  746.0|0.2647  |  -0.0411|    0.1493|Model 6: Full Model with Covariates |
|fixed  |comp_mean_between                                  |   0.0296|    0.0526|    0.5632|  746.0|0.5734  |  -0.0736|    0.1329|Model 6: Full Model with Covariates |
|fixed  |auto_mean_between                                  |   0.1091|    0.0552|    1.9754|  746.0|0.0486  |   0.0007|    0.2176|Model 6: Full Model with Covariates |
|fixed  |relt_mean_between                                  |   0.1172|    0.0591|    1.9827|  746.0|0.0478  |   0.0012|    0.2332|Model 6: Full Model with Covariates |
|fixed  |meetings_count_between                             |  -0.0642|    0.0662|   -0.9702|  746.0|0.3322  |  -0.1941|    0.0657|Model 6: Full Model with Covariates |
|fixed  |meetings_mins_between                              |   0.0028|    0.0013|    2.0664|  746.0|0.0391  |   0.0001|    0.0054|Model 6: Full Model with Covariates |
|fixed  |pa_mean_c                                          |  -0.0203|    0.0354|   -0.5749|  746.0|0.5656  |  -0.0897|    0.0491|Model 6: Full Model with Covariates |
|fixed  |na_mean_c                                          |   0.0021|    0.0336|    0.0617|  746.0|0.9508  |  -0.0638|    0.0680|Model 6: Full Model with Covariates |
|fixed  |br_mean_c                                          |   0.0177|    0.0457|    0.3871|  746.0|0.6988  |  -0.0720|    0.1074|Model 6: Full Model with Covariates |
|fixed  |vio_mean_c                                         |   0.0098|    0.0407|    0.2401|  746.0|0.8103  |  -0.0701|    0.0896|Model 6: Full Model with Covariates |
|fixed  |js_mean_c                                          |   0.0623|    0.0309|    2.0138|  746.0|0.0444  |   0.0016|    0.1230|Model 6: Full Model with Covariates |
|fixed  |age_c                                              |   0.0043|    0.0025|    1.7628|  746.0|0.0783  |  -0.0005|    0.0092|Model 6: Full Model with Covariates |
|fixed  |job_tenure3 to 5 years                             |   0.0516|    0.0619|    0.8337|  746.0|0.4047  |  -0.0700|    0.1732|Model 6: Full Model with Covariates |
|fixed  |job_tenureLess than a year                         |  -0.0231|    0.0742|   -0.3116|  746.0|0.7555  |  -0.1687|    0.1225|Model 6: Full Model with Covariates |
|fixed  |job_tenureMore than 5 years                        |  -0.0152|    0.0609|   -0.2499|  746.0|0.8027  |  -0.1349|    0.1044|Model 6: Full Model with Covariates |
|fixed  |ethnicityArab, Middle Eastern, or North African    |  -0.1867|    0.3272|   -0.5706|  746.0|0.5685  |  -0.8289|    0.4556|Model 6: Full Model with Covariates |
|fixed  |ethnicityAsian                                     |   0.2028|    0.2980|    0.6806|  746.0|0.4963  |  -0.3822|    0.7878|Model 6: Full Model with Covariates |
|fixed  |ethnicityBlack or African American                 |   0.1495|    0.2963|    0.5048|  746.0|0.6139  |  -0.4321|    0.7311|Model 6: Full Model with Covariates |
|fixed  |ethnicityHispanic or Latino                        |   0.0726|    0.2943|    0.2468|  746.0|0.8052  |  -0.5052|    0.6505|Model 6: Full Model with Covariates |
|fixed  |ethnicityNative Hawaiian or other Pacific Islander |   0.3414|    0.4315|    0.7912|  746.0|0.4291  |  -0.5057|    1.1886|Model 6: Full Model with Covariates |
|fixed  |ethnicityPrefer not to say                         |  -0.0756|    0.3378|   -0.2236|  746.0|0.8231  |  -0.7387|    0.5876|Model 6: Full Model with Covariates |
|fixed  |ethnicityTwo or more races                         |   0.1655|    0.3055|    0.5417|  746.0|0.5882  |  -0.4342|    0.7651|Model 6: Full Model with Covariates |
|fixed  |ethnicityWhite or Caucasian                        |   0.0524|    0.2902|    0.1807|  746.0|0.8566  |  -0.5173|    0.6222|Model 6: Full Model with Covariates |
