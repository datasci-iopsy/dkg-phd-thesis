|effect |term                        | estimate| std.error| statistic|    df|p.value | conf.low| conf.high|model                               |
|:------|:---------------------------|--------:|---------:|---------:|-----:|:-------|--------:|---------:|:-----------------------------------|
|fixed  |(Intercept)                 |   1.5714|    0.0559|   28.1158| 335.0|< .001  |   1.4615|    1.6814|Model 0: Unconditional Means        |
|fixed  |(Intercept)                 |   1.5074|    0.0591|   25.4995| 416.3|< .001  |   1.3912|    1.6236|Model 1: Fixed Time                 |
|fixed  |time_c                      |   0.0640|    0.0193|    3.3225| 671.0|< .001  |   0.0262|    0.1018|Model 1: Fixed Time                 |
|fixed  |(Intercept)                 |   1.5074|    0.0552|   27.3250| 335.0|< .001  |   1.3989|    1.6160|Model 2: Random Slope               |
|fixed  |time_c                      |   0.0640|    0.0205|    3.1190| 335.0|0.002   |   0.0236|    0.1043|Model 2: Random Slope               |
|fixed  |(Intercept)                 |   1.4262|    0.0634|   22.4897| 339.9|< .001  |   1.3015|    1.5510|Model 3: L1 Within-Person           |
|fixed  |time_c                      |   0.0452|    0.0189|    2.3888| 343.0|0.0174  |   0.0080|    0.0825|Model 3: L1 Within-Person           |
|fixed  |pf_mean_within              |   0.1651|    0.0430|    3.8426| 658.3|< .001  |   0.0807|    0.2495|Model 3: L1 Within-Person           |
|fixed  |cw_mean_within              |   0.0272|    0.0402|    0.6769| 655.4|0.4987  |  -0.0517|    0.1061|Model 3: L1 Within-Person           |
|fixed  |ee_mean_within              |   0.2215|    0.0430|    5.1530| 613.9|< .001  |   0.1371|    0.3060|Model 3: L1 Within-Person           |
|fixed  |comp_mean_within            |   0.1154|    0.0462|    2.4993| 662.5|0.0127  |   0.0247|    0.2061|Model 3: L1 Within-Person           |
|fixed  |auto_mean_within            |  -0.0048|    0.0340|   -0.1409| 644.4|0.888   |  -0.0715|    0.0619|Model 3: L1 Within-Person           |
|fixed  |relt_mean_within            |   0.0050|    0.0480|    0.1041| 647.6|0.9171  |  -0.0893|    0.0992|Model 3: L1 Within-Person           |
|fixed  |meetings_count_within       |  -0.0157|    0.0290|   -0.5426| 633.7|0.5876  |  -0.0726|    0.0412|Model 3: L1 Within-Person           |
|fixed  |meetings_time_within        |   0.0005|    0.0008|    0.6422| 614.0|0.521   |  -0.0011|    0.0022|Model 3: L1 Within-Person           |
|fixed  |recruitment_sourcesnowball  |   0.4147|    0.1272|    3.2593| 334.0|0.0012  |   0.1644|    0.6650|Model 3: L1 Within-Person           |
|fixed  |(Intercept)                 |  -0.4215|    0.1177|   -3.5804| 334.4|< .001  |  -0.6531|   -0.1899|Model 4: L1 Within + Between        |
|fixed  |time_c                      |   0.0443|    0.0189|    2.3398| 344.0|0.0199  |   0.0071|    0.0815|Model 4: L1 Within + Between        |
|fixed  |pf_mean_within              |   0.1707|    0.0431|    3.9646| 658.8|< .001  |   0.0862|    0.2553|Model 4: L1 Within + Between        |
|fixed  |cw_mean_within              |   0.0239|    0.0403|    0.5947| 655.5|0.5523  |  -0.0551|    0.1030|Model 4: L1 Within + Between        |
|fixed  |ee_mean_within              |   0.2300|    0.0431|    5.3374| 614.5|< .001  |   0.1453|    0.3146|Model 4: L1 Within + Between        |
|fixed  |comp_mean_within            |   0.1232|    0.0463|    2.6620| 662.8|0.008   |   0.0323|    0.2141|Model 4: L1 Within + Between        |
|fixed  |auto_mean_within            |  -0.0006|    0.0340|   -0.0181| 645.1|0.9856  |  -0.0674|    0.0662|Model 4: L1 Within + Between        |
|fixed  |relt_mean_within            |  -0.0069|    0.0481|   -0.1434| 648.4|0.886   |  -0.1014|    0.0876|Model 4: L1 Within + Between        |
|fixed  |meetings_count_within       |  -0.0186|    0.0290|   -0.6393| 633.3|0.5229  |  -0.0755|    0.0384|Model 4: L1 Within + Between        |
|fixed  |meetings_time_within        |   0.0006|    0.0008|    0.6831| 613.4|0.4948  |  -0.0011|    0.0022|Model 4: L1 Within + Between        |
|fixed  |pf_mean_between             |   0.5285|    0.0782|    6.7610| 326.1|< .001  |   0.3747|    0.6823|Model 4: L1 Within + Between        |
|fixed  |cw_mean_between             |  -0.2330|    0.0710|   -3.2817| 326.0|0.0011  |  -0.3727|   -0.0933|Model 4: L1 Within + Between        |
|fixed  |ee_mean_between             |   0.5467|    0.0896|    6.0979| 325.9|< .001  |   0.3703|    0.7230|Model 4: L1 Within + Between        |
|fixed  |comp_mean_between           |   0.1006|    0.0799|    1.2595| 326.0|0.2087  |  -0.0565|    0.2577|Model 4: L1 Within + Between        |
|fixed  |auto_mean_between           |   0.0471|    0.0539|    0.8739| 326.2|0.3828  |  -0.0590|    0.1532|Model 4: L1 Within + Between        |
|fixed  |relt_mean_between           |   0.0905|    0.0954|    0.9480| 326.0|0.3438  |  -0.0973|    0.2783|Model 4: L1 Within + Between        |
|fixed  |meetings_count_between      |   0.2971|    0.0745|    3.9891| 326.4|< .001  |   0.1506|    0.4436|Model 4: L1 Within + Between        |
|fixed  |meetings_time_between       |  -0.0076|    0.0019|   -3.9629| 326.0|< .001  |  -0.0113|   -0.0038|Model 4: L1 Within + Between        |
|fixed  |recruitment_sourcesnowball  |   0.4347|    0.0908|    4.7854| 326.1|< .001  |   0.2560|    0.6135|Model 4: L1 Within + Between        |
|fixed  |(Intercept)                 |   0.0719|    0.1335|    0.5385| 327.0|0.5906  |  -0.1907|    0.3344|Model 5: L1 + L2 Study Variables    |
|fixed  |time_c                      |   0.0439|    0.0189|    2.3195| 344.0|0.021   |   0.0067|    0.0811|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_within              |   0.1765|    0.0431|    4.0950| 658.7|< .001  |   0.0919|    0.2612|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_within              |   0.0228|    0.0403|    0.5660| 655.2|0.5716  |  -0.0563|    0.1020|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_within              |   0.2309|    0.0431|    5.3523| 614.6|< .001  |   0.1462|    0.3156|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_within            |   0.1200|    0.0463|    2.5911| 662.4|0.0098  |   0.0291|    0.2110|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_within            |  -0.0020|    0.0341|   -0.0591| 644.7|0.9529  |  -0.0689|    0.0649|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_within            |  -0.0029|    0.0482|   -0.0592| 648.1|0.9528  |  -0.0974|    0.0917|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_within       |  -0.0172|    0.0290|   -0.5929| 632.5|0.5535  |  -0.0743|    0.0398|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_time_within        |   0.0006|    0.0008|    0.6743| 612.6|0.5004  |  -0.0011|    0.0022|Model 5: L1 + L2 Study Variables    |
|fixed  |pf_mean_between             |   0.4389|    0.0722|    6.0760| 319.0|< .001  |   0.2968|    0.5810|Model 5: L1 + L2 Study Variables    |
|fixed  |cw_mean_between             |  -0.1302|    0.0661|   -1.9703| 319.0|0.0497  |  -0.2601|   -0.0002|Model 5: L1 + L2 Study Variables    |
|fixed  |ee_mean_between             |   0.3906|    0.0842|    4.6414| 318.9|< .001  |   0.2250|    0.5562|Model 5: L1 + L2 Study Variables    |
|fixed  |comp_mean_between           |   0.0662|    0.0743|    0.8903| 319.0|0.374   |  -0.0800|    0.2124|Model 5: L1 + L2 Study Variables    |
|fixed  |auto_mean_between           |   0.0103|    0.0497|    0.2066| 319.1|0.8365  |  -0.0875|    0.1080|Model 5: L1 + L2 Study Variables    |
|fixed  |relt_mean_between           |   0.0116|    0.0884|    0.1309| 319.0|0.8959  |  -0.1623|    0.1854|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_count_between      |   0.2873|    0.0683|    4.2047| 319.2|< .001  |   0.1528|    0.4217|Model 5: L1 + L2 Study Variables    |
|fixed  |meetings_time_between       |  -0.0064|    0.0018|   -3.6373| 319.0|< .001  |  -0.0098|   -0.0029|Model 5: L1 + L2 Study Variables    |
|fixed  |pa_mean_c                   |   0.0692|    0.0698|    0.9921| 319.0|0.3219  |  -0.0681|    0.2065|Model 5: L1 + L2 Study Variables    |
|fixed  |na_mean_c                   |  -0.0124|    0.0712|   -0.1738| 318.9|0.8622  |  -0.1525|    0.1277|Model 5: L1 + L2 Study Variables    |
|fixed  |jis_mean_c                  |  -0.0052|    0.0347|   -0.1511| 319.0|0.88    |  -0.0734|    0.0629|Model 5: L1 + L2 Study Variables    |
|fixed  |des_mean_c                  |   0.0275|    0.0371|    0.7405| 318.9|0.4596  |  -0.0456|    0.1005|Model 5: L1 + L2 Study Variables    |
|fixed  |br_mean_c                   |   0.1281|    0.0651|    1.9676| 318.9|0.05    |   0.0000|    0.2563|Model 5: L1 + L2 Study Variables    |
|fixed  |vio_mean_c                  |   0.0931|    0.0733|    1.2703| 319.0|0.2049  |  -0.0511|    0.2372|Model 5: L1 + L2 Study Variables    |
|fixed  |js_mean_c                   |  -0.1629|    0.0453|   -3.5962| 319.2|< .001  |  -0.2520|   -0.0738|Model 5: L1 + L2 Study Variables    |
|fixed  |recruitment_sourcesnowball  |   0.2600|    0.0855|    3.0398| 319.0|0.0026  |   0.0917|    0.4283|Model 5: L1 + L2 Study Variables    |
|fixed  |(Intercept)                 |   0.0974|    0.1614|    0.6039| 320.4|0.5464  |  -0.2200|    0.4149|Model 6: Full Model with Covariates |
|fixed  |time_c                      |   0.0438|    0.0189|    2.3169| 344.0|0.0211  |   0.0066|    0.0810|Model 6: Full Model with Covariates |
|fixed  |pf_mean_within              |   0.1769|    0.0431|    4.1023| 658.6|< .001  |   0.0922|    0.2615|Model 6: Full Model with Covariates |
|fixed  |cw_mean_within              |   0.0226|    0.0403|    0.5614| 655.0|0.5747  |  -0.0565|    0.1018|Model 6: Full Model with Covariates |
|fixed  |ee_mean_within              |   0.2309|    0.0431|    5.3511| 614.6|< .001  |   0.1461|    0.3156|Model 6: Full Model with Covariates |
|fixed  |comp_mean_within            |   0.1199|    0.0463|    2.5884| 662.3|0.0099  |   0.0289|    0.2109|Model 6: Full Model with Covariates |
|fixed  |auto_mean_within            |  -0.0021|    0.0341|   -0.0606| 644.5|0.9517  |  -0.0690|    0.0648|Model 6: Full Model with Covariates |
|fixed  |relt_mean_within            |  -0.0034|    0.0482|   -0.0699| 648.1|0.9443  |  -0.0979|    0.0912|Model 6: Full Model with Covariates |
|fixed  |meetings_count_within       |  -0.0173|    0.0290|   -0.5968| 632.5|0.5508  |  -0.0744|    0.0397|Model 6: Full Model with Covariates |
|fixed  |meetings_time_within        |   0.0006|    0.0008|    0.6758| 612.5|0.4994  |  -0.0011|    0.0022|Model 6: Full Model with Covariates |
|fixed  |pf_mean_between             |   0.4385|    0.0740|    5.9237| 315.0|< .001  |   0.2928|    0.5841|Model 6: Full Model with Covariates |
|fixed  |cw_mean_between             |  -0.1323|    0.0672|   -1.9699| 315.0|0.0497  |  -0.2645|   -0.0002|Model 6: Full Model with Covariates |
|fixed  |ee_mean_between             |   0.3943|    0.0859|    4.5911| 314.9|< .001  |   0.2253|    0.5632|Model 6: Full Model with Covariates |
|fixed  |comp_mean_between           |   0.0648|    0.0748|    0.8660| 315.0|0.3872  |  -0.0824|    0.2120|Model 6: Full Model with Covariates |
|fixed  |auto_mean_between           |   0.0073|    0.0502|    0.1452| 315.1|0.8846  |  -0.0915|    0.1061|Model 6: Full Model with Covariates |
|fixed  |relt_mean_between           |   0.0112|    0.0891|    0.1257| 315.0|0.9     |  -0.1640|    0.1864|Model 6: Full Model with Covariates |
|fixed  |meetings_count_between      |   0.2910|    0.0689|    4.2257| 315.2|< .001  |   0.1555|    0.4265|Model 6: Full Model with Covariates |
|fixed  |meetings_time_between       |  -0.0064|    0.0018|   -3.6152| 315.0|< .001  |  -0.0099|   -0.0029|Model 6: Full Model with Covariates |
|fixed  |pa_mean_c                   |   0.0673|    0.0706|    0.9529| 315.0|0.3414  |  -0.0716|    0.2062|Model 6: Full Model with Covariates |
|fixed  |na_mean_c                   |  -0.0046|    0.0725|   -0.0634| 314.9|0.9495  |  -0.1472|    0.1380|Model 6: Full Model with Covariates |
|fixed  |jis_mean_c                  |  -0.0041|    0.0351|   -0.1154| 314.9|0.9082  |  -0.0732|    0.0651|Model 6: Full Model with Covariates |
|fixed  |des_mean_c                  |   0.0289|    0.0375|    0.7709| 314.9|0.4413  |  -0.0448|    0.1026|Model 6: Full Model with Covariates |
|fixed  |br_mean_c                   |   0.1290|    0.0657|    1.9627| 314.9|0.0506  |  -0.0003|    0.2584|Model 6: Full Model with Covariates |
|fixed  |vio_mean_c                  |   0.0938|    0.0740|    1.2679| 315.0|0.2058  |  -0.0517|    0.2393|Model 6: Full Model with Covariates |
|fixed  |js_mean_c                   |  -0.1598|    0.0457|   -3.5000| 315.2|< .001  |  -0.2497|   -0.0700|Model 6: Full Model with Covariates |
|fixed  |recruitment_sourcesnowball  |   0.2552|    0.0878|    2.9048| 315.0|0.0039  |   0.0823|    0.4280|Model 6: Full Model with Covariates |
|fixed  |age_c                       |   0.0023|    0.0037|    0.6091| 314.9|0.5429  |  -0.0050|    0.0095|Model 6: Full Model with Covariates |
|fixed  |job_tenure3 to 5 years      |  -0.0686|    0.1063|   -0.6453| 315.0|0.5192  |  -0.2779|    0.1406|Model 6: Full Model with Covariates |
|fixed  |job_tenureLess than a year  |   0.0429|    0.1275|    0.3362| 314.9|0.7369  |  -0.2080|    0.2938|Model 6: Full Model with Covariates |
|fixed  |job_tenureMore than 5 years |  -0.0136|    0.0973|   -0.1397| 315.0|0.889   |  -0.2051|    0.1779|Model 6: Full Model with Covariates |
