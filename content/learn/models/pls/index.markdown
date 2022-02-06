---
title: "Partial least squares 로 하는 다변량 분석"
tags: [recipes,rsample]
categories: [pre-processing]
type: learn-subsection
weight: 6
description: | 
  하나 이상의 결과가 있는 예측 모델을 만들고 적합하기.
---






## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: modeldata, pls, and tidymodels.

"다변량 분석" 은 다중 _아웃컴_ 을 모델링하고, 분석하고 예측하는 것을 의미합니다. 
일반적인 통계 도구들에는 다변량 버전이 있습니다. 
예를 들어, 예측할 두 개의 아웃컴을 의미하는 `y1`, `y2` 열을 가진 데이터셋이 있다고 가정해봅시다. 
`lm()` 함수는 다음과 같이 생겼습니다:


```r
lm(cbind(y1, y2) ~ ., data = dat)
```

이 `cbind` 호출은 꽤 이상한데, 전통적 공식 인프라가 동작방법의 결과입니다.
recipes 패키지는 다루기 훨씬 쉽습니다!
이 장에서 다중 아웃컴을 모델링하는 법을 살펴볼 것입니다.

The data that we'll use has three outcomes. From `?modeldata::meats`:

> "These data are recorded on a Tecator Infratec Food and Feed Analyzer working in the wavelength range 850 - 1050 nm by the Near Infrared Transmission (NIT) principle. Each sample contains finely chopped pure meat with different moisture, fat and protein contents.

> "For each meat sample the data consists of a 100 channel spectrum of absorbances and the contents of moisture (water), fat and protein. The absorbance is `-log10` of the transmittance measured by the spectrometer. The three contents, measured in percent, are determined by analytic chemistry."

The goal is to predict the proportion of the three substances using the chemistry test. There can often be a high degree of between-variable correlations in predictors, and that is certainly the case here. 

To start, let's take the two data matrices (called `endpoints` and `absorp`) and bind them together in a data frame:


```r
library(modeldata)
data(meats)
```

The three _outcomes_ have fairly high correlations also. 

## Preprocessing the data

If the outcomes can be predicted using a linear model, partial least squares (PLS) is an ideal method. PLS models the data as a function of a set of unobserved _latent_ variables that are derived in a manner similar to principal component analysis (PCA). 

PLS, unlike PCA, also incorporates the outcome data when creating the PLS components. Like PCA, it tries to maximize the variance of the predictors that are explained by the components but it also tries to simultaneously maximize the correlation between those components and the outcomes. In this way, PLS _chases_ variation of the predictors and outcomes. 

Since we are working with variances and covariances, we need to standardize the data. The recipe will center and scale all of the variables. 

Many base R functions that deal with multivariate outcomes using a formula require the use of `cbind()` on the left-hand side of the formula to work with the traditional formula methods. In tidymodels, recipes do not; the outcomes can be symbolically "added" together on the left-hand side:


```r
norm_rec <- 
  recipe(water + fat + protein ~ ., data = meats) %>%
  step_normalize(everything()) 
```

Before we can finalize the PLS model, the number of PLS components to retain must be determined. This can be done using performance metrics such as the root mean squared error. However, we can also calculate the proportion of variance explained by the components for the _predictors and each of the outcomes_. This allows an informed choice to be made based on the level of evidence that the situation requires. 

Since the data set isn't large, let's use resampling to measure these proportions. With ten repeats of 10-fold cross-validation, we build the PLS model on 90% of the data and evaluate on the heldout 10%. For each of the 100 models, we extract and save the proportions. 

The folds can be created using the [rsample](https://tidymodels.github.io/rsample/) package and the recipe can be estimated for each resample using the [`prepper()`](https://tidymodels.github.io/rsample/reference/prepper.html) function: 


```r
set.seed(57343)
folds <- vfold_cv(meats, repeats = 10)

folds <- 
  folds %>%
  mutate(recipes = map(splits, prepper, recipe = norm_rec))
```

## Partial least squares

The complicated parts for moving forward are:

1. Formatting the predictors and outcomes into the format that the pls package requires, and
2. Estimating the proportions. 

For the first part, the standardized outcomes and predictors need to be formatted into two separate matrices. Since we used `retain = TRUE` when prepping the recipes, we can `bake()` with `new_data = NULl` to get the processed data back out. To save the data as a matrix, the option `composition = "matrix"` will avoid saving the data as tibbles and use the required format. 

The pls package expects a simple formula to specify the model, but each side of the formula should _represent a matrix_. In other words, we need a data set with two columns where each column is a matrix. The secret to doing this is to "protect" the two matrices using `I()` when adding them to the data frame.

The calculation for the proportion of variance explained is straightforward for the predictors; the function `pls::explvar()` will compute that. For the outcomes, the process is more complicated. A ready-made function to compute these is not obvious but there is some code inside of the summary function to do the computation (see below). 

The function `get_var_explained()` shown here will do all these computations and return a data frame with columns `components`, `source` (for the predictors, water, etc), and the `proportion` of variance that is explained by the components. 



```r
library(pls)

get_var_explained <- function(recipe, ...) {
  
  # Extract the predictors and outcomes into their own matrices
  y_mat <- bake(recipe, new_data = NULL, composition = "matrix", all_outcomes())
  x_mat <- bake(recipe, new_data = NULL, composition = "matrix", all_predictors())
  
  # The pls package prefers the data in a data frame where the outcome
  # and predictors are in _matrices_. To make sure this is formatted
  # properly, use the `I()` function to inhibit `data.frame()` from making
  # all the individual columns. `pls_format` should have two columns.
  pls_format <- data.frame(
    endpoints = I(y_mat),
    measurements = I(x_mat)
  )
  # Fit the model
  mod <- plsr(endpoints ~ measurements, data = pls_format)
  
  # Get the proportion of the predictor variance that is explained
  # by the model for different number of components. 
  xve <- explvar(mod)/100 

  # To do the same for the outcome, it is more complex. This code 
  # was extracted from pls:::summary.mvr. 
  explained <- 
    drop(pls::R2(mod, estimate = "train", intercept = FALSE)$val) %>% 
    # transpose so that components are in rows
    t() %>% 
    as_tibble() %>%
    # Add the predictor proportions
    mutate(predictors = cumsum(xve) %>% as.vector(),
           components = seq_along(xve)) %>%
    # Put into a tidy format that is tall
    pivot_longer(
      cols = c(-components),
      names_to = "source",
      values_to = "proportion"
    )
}
```

We compute this data frame for each resample and save the results in the different columns. 


```r
folds <- 
  folds %>%
  mutate(var = map(recipes, get_var_explained),
         var = unname(var))
```

To extract and aggregate these data, simple row binding can be used to stack the data vertically. Most of the action happens in the first 15 components so let's filter the data and compute the _average_ proportion.


```r
variance_data <- 
  bind_rows(folds[["var"]]) %>%
  filter(components <= 15) %>%
  group_by(components, source) %>%
  summarize(proportion = mean(proportion))
```

The plot below shows that, if the protein measurement is important, you might require 10 or so components to achieve a good representation of that outcome. Note that the predictor variance is captured extremely well using a single component. This is due to the high degree of correlation in those data. 


```r
ggplot(variance_data, aes(x = components, y = proportion, col = source)) + 
  geom_line(alpha = 0.5, size = 1.2) + 
  geom_point() 
```

<img src="figs/plot-1.svg" width="100%" />


## Session information


```
#> ─ Session info  🤷🏻  👉🏽  🔷   ───────────────────────────────────────
#>  hash: person shrugging: light skin tone, backhand index pointing right: medium skin tone, large blue diamond
#> 
#>  setting  value
#>  version  R version 4.1.2 (2021-11-01)
#>  os       macOS Big Sur 10.16
#>  system   x86_64, darwin17.0
#>  ui       X11
#>  language (EN)
#>  collate  en_US.UTF-8
#>  ctype    en_US.UTF-8
#>  tz       Asia/Seoul
#>  date     2022-02-06
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  modeldata  * 0.1.1   2021-07-14 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  pls        * 2.8-0   2021-09-03 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        1.0.0   2022-01-26 [1] CRAN (R 4.1.2)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  tibble     * 3.1.6   2021-11-07 [1] CRAN (R 4.1.0)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.1.0)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.1.0)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.1.0)
#>  yardstick  * 0.0.9   2021-11-22 [1] CRAN (R 4.1.0)
#> 
#>  [1] /Library/Frameworks/R.framework/Versions/4.1/Resources/library
#> 
#> ────────────────────────────────────────────────────────────────────
```
 
