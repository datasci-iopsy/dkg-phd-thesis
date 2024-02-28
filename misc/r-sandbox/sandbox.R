# Install and load the simstudy package if not already installed
# install.packages("simstudy")
library(simstudy)
library(corrplot)

tdef <- defData(varname = "auto0", dist = "normal", formula = 4.08, variance = 1.29)
tdef <- defData(tdef, varname = "comp0", dist = "normal", formula = 4.03, variance = 1.29)
tdef <- defData(tdef, varname = "rela0", dist = "normal", formula = 3.81, variance = 1.41)
tdef <- defData(tdef, varname = "burn0", dist = "normal", formula = "auto0 * 0.35 + comp0 * 0.37 + rela0 * 0.29 + rnorm(500)", variance = 1)

# Set seed for reproducibility
set.seed(483726)

dtTrial <- genData(500, tdef)
dtTrial

corrplot::corrplot(cor())
