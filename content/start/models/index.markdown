---
title: "모델 만들기"
weight: 1
tags: [parsnip, broom]
categories: [model fitting]
description: | 
  Get started by learning how to specify and train a model using tidymodels.
---







## 들어가기 {#intro}

tidymodels 를 사용해서 통계 모형을 어떻게 만들까요? 이 문서에서 함께 단계적으로 알아볼 것입니다. 데이터부터 시작해서 [parsnip 패키지](https://tidymodels.github.io/parsnip/) 를 사용하여 각종 엔진들로 모델을 만들고 훈련시키는 법을 배우고 이러한 함수들을 설계하는 이유를 배울 것입니다. 

To use code in this article,  you will need to install the following packages: broom.mixed, dotwhisker, readr, rstanarm, and tidymodels.


```r
library(tidymodels)  # for the parsnip package, along with the rest of tidymodels

# Helper packages
library(readr)       # for importing data
library(broom.mixed) # for converting bayesian models to tidy tibbles
library(dotwhisker)  # for visualizing regression results
```


{{< test-drive url="https://rstudio.cloud/project/2674862" >}}


## 성게 데이터 {#data}

[Constable (1993)](https://link.springer.com/article/10.1007/BF00349318) 데이터에서 사육법에 따른 성게 크기의 차이를 살펴봅시다. 실험 시작점에서의 성게의 초기 크기가 아마도 얼마나 클 수 있는지에 대해 영향을 줄 것입니다.

To start, let's read our urchins data into R, which we'll do by providing [`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html) with a url where our CSV data is located ("<https://tidymodels.org/start/models/urchins.csv>"):


```r
urchins <-
  # Data were assembled for a tutorial 
  # at https://www.flutterbys.com.au/stats/tut/tut7.5a.html
  read_csv("https://tidymodels.org/start/models/urchins.csv") %>% 
  # Change the names to be a little more verbose
  setNames(c("food_regime", "initial_volume", "width")) %>% 
  # Factors are very helpful for modeling, so we convert one column
  mutate(food_regime = factor(food_regime, levels = c("Initial", "Low", "High")))
#> Rows: 72 Columns: 3
#> ── Column specification ──────────────────────────────────────────────
#> Delimiter: ","
#> chr (1): TREAT
#> dbl (2): IV, SUTW
#> 
#> ℹ Use `spec()` to retrieve the full column specification for this data.
#> ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.
```

Let's take a quick look at the data:


```r
urchins
#> # A tibble: 72 × 3
#>    food_regime initial_volume width
#>    <fct>                <dbl> <dbl>
#>  1 Initial                3.5 0.01 
#>  2 Initial                5   0.02 
#>  3 Initial                8   0.061
#>  4 Initial               10   0.051
#>  5 Initial               13   0.041
#>  6 Initial               13   0.061
#>  7 Initial               15   0.041
#>  8 Initial               15   0.071
#>  9 Initial               16   0.092
#> 10 Initial               17   0.051
#> # … with 62 more rows
```

The urchins data is a [tibble](https://tibble.tidyverse.org/index.html). If you are new to tibbles, the best place to start is the [tibbles chapter](https://r4ds.had.co.nz/tibbles.html) in *R for Data Science*. For each of the 72 urchins, we know their:


+ 실험 사육법 그룹 (`food_regime`: `Initial` 혹은 `Low` 혹은 `High`),
+ 실험 시작시점에서의 밀리미터 단위의 크기 (`initial_volume`)
+ 실험 마지막의 크기 (`width`).

모델링의 첫단계로 데이터를 시각화해 보는 것은 좋은 방법입니다:


```r
ggplot(urchins,
       aes(x = initial_volume, 
           y = width, 
           group = food_regime, 
           col = food_regime)) + 
  geom_point() + 
  geom_smooth(method = lm, se = FALSE) +
  scale_color_viridis_d(option = "plasma", end = .7)
#> `geom_smooth()` using formula 'y ~ x'
```

<img src="figs/urchin-plot-1.svg" width="672" />

We can see that urchins that were larger in volume at the start of the experiment tended to have wider sutures at the end, but the slopes of the lines look different so this effect may depend on the feeding regime condition.

## 모델 구축 및 적합 {#build-model}

A standard two-way analysis of variance ([ANOVA](https://www.itl.nist.gov/div898/handbook/prc/section4/prc43.htm)) model makes sense for this dataset because we have both a continuous predictor and a categorical predictor. Since the slopes appear to be different for at least two of the feeding regimes, let's build a model that allows for two-way interactions. Specifying an R formula with our variables in this way: 


```r
width ~ initial_volume * food_regime
```

를 하면, 회귀 모형이 각 사육법에 따라 다른 기울기와 절편을 갖게 됩니다.

For this kind of model, ordinary least squares is a good initial approach. With tidymodels, we start by specifying the _functional form_ of the model that we want using the [parsnip package](https://tidymodels.github.io/parsnip/). 수치형 출력값이 있고, 모델이 기울기와 절편들에 대해 선형이므로, 이러한 모델 타잎은 ["linear regression (선형회귀)"](https://tidymodels.github.io/parsnip/reference/linear_reg.html) 입니다. 이를 다음과 같이 선언합니다: 



```r
linear_reg()
#> Linear Regression Model Specification (regression)
#> 
#> Computational engine: lm
```

That is pretty underwhelming since, on its own, it doesn't really do much. However, now that the type of model has been specified, a method for _fitting_ or training the model can be stated using the **engine**. The engine value is often a mash-up of the software that can be used to fit or train the model as well as the estimation method. 예를 들어, 엔진을 `lm` 으로 두어 ordinary least squares 를 사용합니다:


```r
linear_reg() %>% 
  set_engine("lm")
#> Linear Regression Model Specification (regression)
#> 
#> Computational engine: lm
```

[`linear_reg() 문서`](https://tidymodels.github.io/parsnip/reference/linear_reg.html) 에는 가능한 엔진들이 나열되어 있습니다. 이 모델 객체를 `lm_mod` 으로 저장할 것입니다.


```r
lm_mod <- 
  linear_reg() %>% 
  set_engine("lm")
```

이제 [`fit()`](https://tidymodels.github.io/parsnip/reference/fit.html) 함수를 사용하여 모형을 추정하고 훈련할 수 있습니다:


```r
lm_fit <- 
  lm_mod %>% 
  fit(width ~ initial_volume * food_regime, data = urchins)
lm_fit
#> parsnip model object
#> 
#> Fit time:  4ms 
#> 
#> Call:
#> stats::lm(formula = width ~ initial_volume * food_regime, data = data)
#> 
#> Coefficients:
#>                    (Intercept)                  initial_volume  
#>                      0.0331216                       0.0015546  
#>                 food_regimeLow                 food_regimeHigh  
#>                      0.0197824                       0.0214111  
#>  initial_volume:food_regimeLow  initial_volume:food_regimeHigh  
#>                     -0.0012594                       0.0005254
```

Perhaps our analysis requires a description of the model parameter estimates and their statistical properties. `lm` 객체에 대한 `summary()` 함수를 사용할 수 있지만, 결과를 복잡한 형태로 제공한다. 많은 모델에는, 예측한대로 그리고 유용한 형태로 결과를 요약하는 `tidy()` 방법이 있습니다 (예: 표준 열 이름을 가진 데이터프레임):


```r
tidy(lm_fit)
#> # A tibble: 6 × 5
#>   term                            estimate std.error statistic  p.value
#>   <chr>                              <dbl>     <dbl>     <dbl>    <dbl>
#> 1 (Intercept)                     0.0331    0.00962      3.44  0.00100 
#> 2 initial_volume                  0.00155   0.000398     3.91  0.000222
#> 3 food_regimeLow                  0.0198    0.0130       1.52  0.133   
#> 4 food_regimeHigh                 0.0214    0.0145       1.47  0.145   
#> 5 initial_volume:food_regimeLow  -0.00126   0.000510    -2.47  0.0162  
#> 6 initial_volume:food_regimeHigh  0.000525  0.000702     0.748 0.457
```

이러한 종류의 출력은 dotwhisker 패키지를 사용하여 우리의 회귀 결과의 dot-and-whisker 플롯을 그려볼 수 있습니다:


```r
tidy(lm_fit) %>% 
  dwplot(dot_args = list(size = 2, color = "black"),
         whisker_args = list(color = "black"),
         vline = geom_vline(xintercept = 0, colour = "grey50", linetype = 2))
```

<img src="figs/dwplot-1.svg" width="672" />


## 모델을 이용하여 예측하기 {#predict-model}

적합된 객체 `lm_fit` 에는 `lm` model output built-in 이 있어, `lm_fit$fit` 로 접근할 수 있지만, 적합된 parsnip 모델 객체에는 예측에 관련하여 장점 몇 개가 있습니다. 

Suppose that, for a publication, it would be particularly interesting to make a plot of the mean body size for urchins that started the experiment with an initial volume of 20ml. To create such a graph, we start with some new example data that we will make predictions for, to show in our graph:


```r
new_points <- expand.grid(initial_volume = 20, 
                          food_regime = c("Initial", "Low", "High"))
new_points
#>   initial_volume food_regime
#> 1             20     Initial
#> 2             20         Low
#> 3             20        High
```

예측 결과들을 얻기 위해, `predict()` 함수를 사용하여 20ml 에서 평균값을 구할 수 있습니다.

변동성에 대해 잘 전달하는 것도 중요하기 때문에, 예측 신뢰구간을 구할 필요가 있습니다. `lm()` 를 이용하여 모델을 직접 적합했다면, `predict.lm()` 의 [문서 페이지](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/predict.lm.html) 를 몇 분동안 읽으면 어떻게 하는지 알 수 있을 것입니다. 하지만, 성게 크기를 예측하기 위해 다른 모형을 사용하기를 결정했다면 (_스포일러:_ 예정됨), 완전히 다른 문법이 필요할 가능성이 매우 높습니다.

tidymodels 에서는 예측값들의 타잎이 표준화되기 때문에 이러한 값을 얻기 위해 같은 문법을 사용할 수 있다.

우선, 몸통폭 평균값을 만들어 보자:


```r
mean_pred <- predict(lm_fit, new_data = new_points)
mean_pred
#> # A tibble: 3 × 1
#>    .pred
#>    <dbl>
#> 1 0.0642
#> 2 0.0588
#> 3 0.0961
```

When making predictions, the tidymodels convention is to always produce a tibble of results with standardized column names. This makes it easy to combine the original data and the predictions in a usable format: 


```r
conf_int_pred <- predict(lm_fit, 
                         new_data = new_points, 
                         type = "conf_int")
conf_int_pred
#> # A tibble: 3 × 2
#>   .pred_lower .pred_upper
#>         <dbl>       <dbl>
#> 1      0.0555      0.0729
#> 2      0.0499      0.0678
#> 3      0.0870      0.105

# Now combine: 
plot_data <- 
  new_points %>% 
  bind_cols(mean_pred) %>% 
  bind_cols(conf_int_pred)

# and plot:
ggplot(plot_data, aes(x = food_regime)) + 
  geom_point(aes(y = .pred)) + 
  geom_errorbar(aes(ymin = .pred_lower, 
                    ymax = .pred_upper),
                width = .2) + 
  labs(y = "urchin size")
```

<img src="figs/lm-all-pred-1.svg" width="672" />

## 다른 엔진을 사용한 모델 {#new-engine}

Every one on your team is happy with that plot _except_ that one person who just read their first book on [Bayesian analysis](https://bayesian.org/what-is-bayesian-analysis/). They are interested in knowing if the results would be different if the model were estimated using a Bayesian approach. In such an analysis, a [_prior distribution_](https://towardsdatascience.com/introduction-to-bayesian-linear-regression-e66e60791ea7) needs to be declared for each model parameter that represents the possible values of the parameters (before being exposed to the observed data). After some discussion, the group agrees that the priors should be bell-shaped but, since no one has any idea what the range of values should be, to take a conservative approach and make the priors _wide_ using a Cauchy distribution (which is the same as a t-distribution with a single degree of freedom).

`linear_reg()` 은 stan 엔진이 있다는 것을 알게 되었다. 이러한 사전 분포 인수들은 Stan 소프트웨어에 특화되기 때문에, [`parsnip::set_engine()`](https://tidymodels.github.io/parsnip/reference/set_engine.html) 의 인수의 형태로 전달된다. 

The [documentation](https://mc-stan.org/rstanarm/articles/priors.html) on the rstanarm package shows us that the `stan_glm()` function can be used to estimate this model, and that the function arguments that need to be specified are called `prior` and `prior_intercept`. It turns out that `linear_reg()` has a [`stan` engine](https://tidymodels.github.io/parsnip/reference/linear_reg.html#details). Since these prior distribution arguments are specific to the Stan software, they are passed as arguments to [`parsnip::set_engine()`](https://tidymodels.github.io/parsnip/reference/set_engine.html). After that, the same exact `fit()` call is used:


```r
# set the prior distribution
prior_dist <- rstanarm::student_t(df = 1)

set.seed(123)

# make the parsnip model
bayes_mod <-   
  linear_reg() %>% 
  set_engine("stan", 
             prior_intercept = prior_dist, 
             prior = prior_dist) 

# train the model
bayes_fit <- 
  bayes_mod %>% 
  fit(width ~ initial_volume * food_regime, data = urchins)

print(bayes_fit, digits = 5)
#> parsnip model object
#> 
#> Fit time:  16.3s 
#> stan_glm
#>  family:       gaussian [identity]
#>  formula:      width ~ initial_volume * food_regime
#>  observations: 72
#>  predictors:   6
#> ------
#>                                Median   MAD_SD  
#> (Intercept)                     0.03281  0.00992
#> initial_volume                  0.00157  0.00041
#> food_regimeLow                  0.01990  0.01286
#> food_regimeHigh                 0.02136  0.01519
#> initial_volume:food_regimeLow  -0.00126  0.00052
#> initial_volume:food_regimeHigh  0.00052  0.00073
#> 
#> Auxiliary parameter(s):
#>       Median  MAD_SD 
#> sigma 0.02144 0.00192
#> 
#> ------
#> * For help interpreting the printed output see ?print.stanreg
#> * For info on the priors used see ?prior_summary.stanreg
```

This kind of Bayesian analysis (like many models) involves randomly generated numbers in its fitting procedure. We can use `set.seed()` to ensure that the same (pseudo-)random numbers are generated each time we run this code. The number `123` isn't special or related to our data; it is just a "seed" used to choose random numbers.

파라미터 표를 새로 얻기 위해, 또 한번 `tidy()` 방법을 사용할 수 있습니다:


```r
tidy(bayes_fit, conf.int = TRUE)
#> # A tibble: 6 × 5
#>   term                            estimate std.error  conf.low conf.high
#>   <chr>                              <dbl>     <dbl>     <dbl>     <dbl>
#> 1 (Intercept)                     0.0328    0.00992   0.0168    0.0488  
#> 2 initial_volume                  0.00157   0.000405  0.000893  0.00224 
#> 3 food_regimeLow                  0.0199    0.0129   -0.00140   0.0420  
#> 4 food_regimeHigh                 0.0214    0.0152   -0.00356   0.0464  
#> 5 initial_volume:food_regimeLow  -0.00126   0.000516 -0.00210  -0.000407
#> 6 initial_volume:food_regimeHigh  0.000517  0.000732 -0.000691  0.00171
```

A goal of the tidymodels packages is that the **interfaces to common tasks are standardized** (as seen in the `tidy()` results above). The same is true for getting predictions; we can use the same code even though the underlying packages use very different syntax:


```r
bayes_plot_data <- 
  new_points %>% 
  bind_cols(predict(bayes_fit, new_data = new_points)) %>% 
  bind_cols(predict(bayes_fit, new_data = new_points, type = "conf_int"))

ggplot(bayes_plot_data, aes(x = food_regime)) + 
  geom_point(aes(y = .pred)) + 
  geom_errorbar(aes(ymin = .pred_lower, ymax = .pred_upper), width = .2) + 
  labs(y = "urchin size") + 
  ggtitle("Bayesian model with t(1) prior distribution")
```

<img src="figs/stan-pred-1.svg" width="672" />

This isn't very different from the non-Bayesian results (except in interpretation). 

{{% note %}} The [parsnip](https://parsnip.tidymodels.org/) package can work with many model types, engines, and arguments. Check out [tidymodels.org/find/parsnip](/find/parsnip/) to see what is available. {{%/ note %}}

## Why does it work that way? {#why}

The extra step of defining the model using a function like `linear_reg()` might seem superfluous since a call to `lm()` is much more succinct. However, the problem with standard modeling functions is that they don't separate what you want to do from the execution. For example, the process of executing a formula has to happen repeatedly across model calls even when the formula does not change; we can't recycle those computations. 

Also, using the tidymodels framework, we can do some interesting things by incrementally creating a model (instead of using single function call). [Model tuning](/start/tuning/) with tidymodels uses the specification of the model to declare what parts of the model should be tuned. That would be very difficult to do if `linear_reg()` immediately fit the model. 

If you are familiar with the tidyverse, you may have noticed that our modeling code uses the magrittr pipe (`%>%`). With dplyr and other tidyverse packages, the pipe works well because all of the functions take the _data_ as the first argument. For example: 


```r
urchins %>% 
  group_by(food_regime) %>% 
  summarize(med_vol = median(initial_volume))
#> # A tibble: 3 × 2
#>   food_regime med_vol
#>   <fct>         <dbl>
#> 1 Initial        20.5
#> 2 Low            19.2
#> 3 High           15
```

whereas the modeling code uses the pipe to pass around the _model object_:


```r
bayes_mod %>% 
  fit(width ~ initial_volume * food_regime, data = urchins)
```

This may seem jarring if you have used dplyr a lot, but it is extremely similar to how ggplot2 operates:


```r
ggplot(urchins,
       aes(initial_volume, width)) +      # returns a ggplot object 
  geom_jitter() +                         # same
  geom_smooth(method = lm, se = FALSE) +  # same                    
  labs(x = "Volume", y = "Width")         # etc
```


## Session information {#session-info}


```
#> ─ Session info ───────────────────────────────────────────────────────────────
#>  setting  value                       
#>  version  R version 4.0.5 (2021-03-31)
#>  os       macOS Big Sur 10.16         
#>  system   x86_64, darwin17.0          
#>  ui       X11                         
#>  language (EN)                        
#>  collate  en_US.UTF-8                 
#>  ctype    en_US.UTF-8                 
#>  tz       Asia/Seoul                  
#>  date     2021-10-24                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package     * version date       lib source        
#>  broom       * 0.7.9   2021-07-27 [1] CRAN (R 4.0.2)
#>  broom.mixed * 0.2.6   2020-05-17 [1] CRAN (R 4.0.2)
#>  dials       * 0.0.10  2021-09-10 [1] CRAN (R 4.0.2)
#>  dotwhisker  * 0.7.4   2021-09-02 [1] CRAN (R 4.0.2)
#>  dplyr       * 1.0.7   2021-06-18 [1] CRAN (R 4.0.2)
#>  ggplot2     * 3.3.5   2021-06-25 [1] CRAN (R 4.0.2)
#>  infer       * 1.0.0   2021-08-13 [1] CRAN (R 4.0.2)
#>  parsnip     * 0.1.7   2021-07-21 [1] CRAN (R 4.0.2)
#>  purrr       * 0.3.4   2020-04-17 [1] CRAN (R 4.0.2)
#>  readr       * 2.0.1   2021-08-10 [1] CRAN (R 4.0.2)
#>  recipes     * 0.1.17  2021-09-27 [1] CRAN (R 4.0.2)
#>  rlang         0.4.11  2021-04-30 [1] CRAN (R 4.0.2)
#>  rsample     * 0.1.0   2021-05-08 [1] CRAN (R 4.0.2)
#>  rstanarm    * 2.21.1  2020-07-20 [1] CRAN (R 4.0.2)
#>  tibble      * 3.1.5   2021-09-30 [1] CRAN (R 4.0.2)
#>  tidymodels  * 0.1.4   2021-10-01 [1] CRAN (R 4.0.2)
#>  tune        * 0.1.6   2021-07-21 [1] CRAN (R 4.0.2)
#>  workflows   * 0.2.4   2021-10-12 [1] CRAN (R 4.0.2)
#>  yardstick   * 0.0.8   2021-03-28 [1] CRAN (R 4.0.2)
#> 
#> [1] /Library/Frameworks/R.framework/Versions/4.0/Resources/library
```
