---
title: "모델 만들기"
weight: 1
tags: [parsnip, broom]
categories: [model fitting]
description: | 
  tidymodels 를 사용하여 모델을 명시하고 훈련하는 법을 배운다.
---







## 들어가기 {#intro}

tidymodels 를 사용해서 통계모형을 어떻게 만들까요? 이 문서에서 함께 단계적으로 알아볼 것입니다. 데이터부터 시작해서 [parsnip 패키지](https://tidymodels.github.io/parsnip/) 를 사용하여 각종 엔진들로 모델을 만들고 훈련시키는 법을 배우고 이러한 함수들을 설계하는 이유를 배울 것입니다. 

이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: broom.mixed, dotwhisker, readr, rstanarm, and tidymodels.


```r
library(tidymodels)  # for the parsnip package, along with the rest of tidymodels

# Helper packages
library(readr)       # for importing data
library(broom.mixed) # for converting bayesian models to tidy tibbles
library(dotwhisker)  # for visualizing regression results
```


{{< test-drive url="https://rstudio.cloud/project/2674862" >}}


## 성게 데이터 {#data}

[Constable (1993)](https://link.springer.com/article/10.1007/BF00349318) 데이터에서 사육법에 따른 성게 크기 차이를 살펴봅시다. 실험 시작점에서의 성게의 초기 크기가 아마도 얼마나 클 수 있는지에 대해 영향을 줄 것입니다.

이제, 성게 데이터를 R 로 읽어봅시다. [`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html) 에 CSV 데이터 위치의 url("<https://tidymodels.org/start/models/urchins.csv>")을 입력하면 됩니다:


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

데이터를 빠르게 한 번 봅시다.


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

성게 데이터는 [tibble](https://tibble.tidyverse.org/index.html) 입니다. tibble 이 처음이라면, *R for Data Science* 의 [tibbles 챕터(한국어)](https://bookdown.org/sulgi/r4ds/tibbles.html) 가 가장 쉽게 입문할 수 있는 곳입니다. 72 개 성게 각각에 대해 다음의 정보가 있습니다:

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

실험 시작시점에 부피가 큰 성게들은 실험종료시점에 더 넓은 성체를 갖는 경향이 있음을 알 수 있지만, 기울기들이 다르기 때문에 이러한 효과가 사육법 조건에 따라 다른 것처럼 보입니다.

## 모델 구축 및 적합 {#build-model}

이러한 데이터셋에 two way 분산분석 ([ANOVA](https://www.itl.nist.gov/div898/handbook/prc/section4/prc43.htm)) 모델을 사용할 수 있는데, 연속형 설명변수와 명목형 설명변수가 있기 때문입니다. 직선의 기울기가 적어도 두 개 이상의 사육법에 대해 달라 보이기 때문에, two-way interaction 을 가진 모델을 만들어 봅시다. 다음과 같이 변수들로 R 공식을 선언합니다.


```r
width ~ initial_volume * food_regime
```

initial volume 에 따라 변하는 위의 회귀 모형은 각 사육법에 대해 다른 기울기와 절편을 갖게 됩니다.

이러한 모델에 대해, ordinary least squares 는 처음으로 시도해보기 좋은 방법입니다. tidymodels 에서 원하는 모델의 _함수포맷_ 을 [parsnip package](https://tidymodels.github.io/parsnip/)를 사용하여 명시합니다. 수치형 출력값이 있고, 모델이 기울기와 절편들에 대해 선형이므로, 이러한 모델 타잎은 ["linear regression (선형회귀)"](https://tidymodels.github.io/parsnip/reference/linear_reg.html) 입니다. 이를 다음과 같이 선언합니다: 



```r
linear_reg()
#> Linear Regression Model Specification (regression)
#> 
#> Computational engine: lm
```

이는 정작 하는 것이 거의 없기 때문에, 꽤 시시합니다. 하지만, 모델의 유형이 명시되었기 때문에, 이제 **engine** 모델을 사용하여 _적합_ 이나 훈련을 명시할 수 있습니다. 
엔진값은 모델을 훈련시키거나 적합하는데 사용되는 소프트웨어와 추정방법의 결합(mash-up)인 경우가 많습니다. 예를 들어, 엔진을 `lm` 으로 두어 ordinary least squares 를 사용합니다:


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
#> Fit time:  2ms 
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

아마도 우리 분석에서 모델 파라미터 추정값과 통계적 특징값들에 대해 descirption 이 필요합니다. `lm` 객체에 대한 `summary()` 함수를 사용할 수 있지만, 결과를 복잡한 형태로 제공합니다. 많은 모델에는, 예측한대로 그리고 유용한 형태로 결과를 요약하는 `tidy()` 방법이 있습니다 (예: 표준 열 이름을 가진 데이터프레임):


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

우선, 몸통폭 평균값을 만들어 봅시다:


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

팀원 모두가 이 플롯에 만족했지_만_ [Bayesian analysis](https://bayesian.org/what-is-bayesian-analysis/)에 관한 첫번째 책을 읽은 한사람은 그렇지 않았습니다. 그들은 모델이 베이지언 방법으로 추정했다면 결과가 달랐을지에 관해 관심이 있습니다. 이러한 분석에서 [_prior distribution_](https://towardsdatascience.com/introduction-to-bayesian-linear-regression-e66e60791ea7)이 각 모델 파라미터에 관해 파라미터로 가능한 값들이 (관측 데이터에 노출되기 전에) 선언되어야 합니다. 논의 끝에, 이 그룹은 prior 가 종모양이지만, 값의 범위가 어떻게 되어야 하는지에 관한 아이디어가 아무도 없었기 때문에, 보수적인 방법을 취해서, 코시 분포 (자유도 1인 t-분포와 동일) 를 사용하여 prior 를 _넓게_ 만들기로 동의합니다.

`linear_reg()` 은 stan 엔진이 있다는 것을 알게 되었습니다. 이러한 사전 분포 인수들은 Stan 소프트웨어에 특화되기 때문에, [`parsnip::set_engine()`](https://tidymodels.github.io/parsnip/reference/set_engine.html) 의 인수의 형태로 전달됩니다. 

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
#> Fit time:  16.5s 
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

## 어떤 작동원리를 가진것일까? {#why}

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
#> ─ Session info  🕵🏼  👱🏼  💥   ──────────────────────────────────────
#>  hash: detective: medium-light skin tone, person: medium-light skin tone, blond hair, collision
#> 
#>  setting  value
#>  version  R version 4.1.1 (2021-08-10)
#>  os       macOS Big Sur 10.16
#>  system   x86_64, darwin17.0
#>  ui       X11
#>  language (EN)
#>  collate  en_US.UTF-8
#>  ctype    en_US.UTF-8
#>  tz       Asia/Seoul
#>  date     2021-12-17
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package     * version date (UTC) lib source
#>  broom       * 0.7.10  2021-10-31 [1] CRAN (R 4.1.0)
#>  broom.mixed * 0.2.7   2021-07-07 [1] CRAN (R 4.1.0)
#>  dials       * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dotwhisker  * 0.7.4   2021-09-02 [1] CRAN (R 4.1.0)
#>  dplyr       * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2     * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer       * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  parsnip     * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr       * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  readr       * 2.1.0   2021-11-11 [1] CRAN (R 4.1.0)
#>  recipes     * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang         0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
#>  rsample     * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  rstanarm    * 2.21.1  2020-07-20 [1] CRAN (R 4.1.0)
#>  tibble      * 3.1.6   2021-11-07 [1] CRAN (R 4.1.0)
#>  tidymodels  * 0.1.4   2021-10-01 [1] CRAN (R 4.1.0)
#>  tune        * 0.1.6   2021-07-21 [1] CRAN (R 4.1.0)
#>  workflows   * 0.2.4   2021-10-12 [1] CRAN (R 4.1.0)
#>  yardstick   * 0.0.9   2021-11-22 [1] CRAN (R 4.1.0)
#> 
#>  [1] /Library/Frameworks/R.framework/Versions/4.1/Resources/library
#> 
#> ────────────────────────────────────────────────────────────────────
```
