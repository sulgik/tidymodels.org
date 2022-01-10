---
title: "부트스트랩 리샘플링과 타이디한 회귀 모델"
tags: [rsample, broom]
categories: [statistical analysis, resampling]
type: learn-subsection
weight: 3
description: | 
  부트스트랩 리샘플링을 적용하여 모델 파라미터에서 불확실성을 추정하기.
---






## 들어가기

이 장은 tidymodels 패키지만 필요로 합니다.

적합된 모델들을 타이디한 방법으로 결합하면 부트스트래핑이나 퍼뮤테이션 테스트를 하기 편리합니다. 이러한 방법들은 예를 들면 [Andrew MacDonald here](https://rstudio-pubs-static.s3.amazonaws.com/19698_a4c472606e3c43e4b94720506e49bb7b.html)에 의해 살펴본 적이 있고, [해들리는 dplyr 에 잠재적인 확장으로써 부트스트래핑에 효율적인 서포트를 탐색한 적이 있습니다](https://github.com/hadley/dplyr/issues/269). tidymodels 패키지 [broom](https://broom.tidyverse.org/) 은 이러한 분석을 수행함에 있어 [dplyr](https://dplyr.tidyverse.org/) 에 자연스럽게 녹아듭니다.

부트스트래핑은 데이터셋을 대치하면서 랜덤하게 샘플링한 뒤 각 부트스태랩된 데이터(bootstraped replicate)에 개별적으로 분석을 수행하는 것으로 이루어져 있습니다. 결과 추정치에서의 분산은 그 후 우리 추정값에서의 분산의 좋은 근사값이 됩니다.

`mtcars` 데이터셋에서 무게/마일리지 관계에 비선형 모델을 적합하고 싶다고 해봅시다.


```r
library(tidymodels)

ggplot(mtcars, aes(mpg, wt)) + 
    geom_point()
```

<img src="figs/unnamed-chunk-1-1.svg" width="672" />

(`nls()` 함수를 통해) nonlinear least squares 방법을 사용하여 모델을 적합할 수 있습니다.


```r
nlsfit <- nls(mpg ~ k / wt + b, mtcars, start = list(k = 1, b = 0))
summary(nlsfit)
#> 
#> Formula: mpg ~ k/wt + b
#> 
#> Parameters:
#>   Estimate Std. Error t value Pr(>|t|)    
#> k    45.83       4.25   10.79  7.6e-12 ***
#> b     4.39       1.54    2.85   0.0077 ** 
#> ---
#> Signif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1
#> 
#> Residual standard error: 2.77 on 30 degrees of freedom
#> 
#> Number of iterations to convergence: 1 
#> Achieved convergence tolerance: 2.88e-08

ggplot(mtcars, aes(wt, mpg)) +
    geom_point() +
    geom_line(aes(y = predict(nlsfit)))
```

<img src="figs/unnamed-chunk-2-1.svg" width="672" />
이렇게 하면 파라미터의 p-value 와 신뢰구간을 얻을 수 있지만, 이들은 실제 데이터에서는 만족하지 않는 모델 가정에 기반한 것입니다. 부트스트래핑은 데이터 성질에 더 로버스트한 신뢰구간과 예측값을 제공하는 널리사용되는 방법입니다.

## 부트스트래핑 모델

rsample 패키지의 `bootstraps()` 함수를 사용하여 부트스트랩 데이터를 샘플할 수 있습니다
우선, 데이터의 각 데이터가 복원 랜덤 샘플링된, 2000 부트스트랩 데이터들을 만듭니다. 결과 객체는 `rset` 인데, `rsplit` 객체들을 하나의 열로 가지고 있는 데이터프레임이 됩니다.

`rsplit` 객체에는 두 개의 메인 구성요소가 있습니다: 분석 데이터셋과 평가 데이터셋이며 각각 `analysis(rsplit)` 과 `assessment(rsplit)` 으로 접근할 수 있습니다. 부트스트랩 샘플에 대해 분석 데이터셋은 부트스트램 샘플 자체이고, 평가 데이터셋은 out-of-bag 샘플들로 구성됩니다.


```r
set.seed(27)
boots <- bootstraps(mtcars, times = 2000, apparent = TRUE)
boots
#> # Bootstrap sampling with apparent sample 
#> # A tibble: 2,001 × 2
#>    splits          id           
#>    <list>          <chr>        
#>  1 <split [32/13]> Bootstrap0001
#>  2 <split [32/10]> Bootstrap0002
#>  3 <split [32/13]> Bootstrap0003
#>  4 <split [32/11]> Bootstrap0004
#>  5 <split [32/9]>  Bootstrap0005
#>  6 <split [32/10]> Bootstrap0006
#>  7 <split [32/11]> Bootstrap0007
#>  8 <split [32/13]> Bootstrap0008
#>  9 <split [32/11]> Bootstrap0009
#> 10 <split [32/11]> Bootstrap0010
#> # … with 1,991 more rows
```

각 부트스트랩 샘플에 `nls()` 모델을 적합하기 위해 도우미 함수를 생성해보고 `purr::map()` 을 이용하여 이 함수를 모든 부트스트랩 샘플들에 한번에 적용해 봅시다. 유사하게, 중첩을 풀어서 타이디한 계수 정보를 가진 열 하나를 생성합니다.


```r
fit_nls_on_bootstrap <- function(split) {
    nls(mpg ~ k / wt + b, analysis(split), start = list(k = 1, b = 0))
}

boot_models <-
  boots %>% 
  mutate(model = map(splits, fit_nls_on_bootstrap),
         coef_info = map(model, tidy))

boot_coefs <- 
  boot_models %>% 
  unnest(coef_info)
```

The unnested coefficient information contains a summary of each replication combined in a single data frame:


```r
boot_coefs
#> # A tibble: 4,002 × 8
#>    splits          id          model term  estimate std.error statistic  p.value
#>    <list>          <chr>       <lis> <chr>    <dbl>     <dbl>     <dbl>    <dbl>
#>  1 <split [32/13]> Bootstrap0… <nls> k        42.1       4.05     10.4  1.91e-11
#>  2 <split [32/13]> Bootstrap0… <nls> b         5.39      1.43      3.78 6.93e- 4
#>  3 <split [32/10]> Bootstrap0… <nls> k        49.9       5.66      8.82 7.82e-10
#>  4 <split [32/10]> Bootstrap0… <nls> b         3.73      1.92      1.94 6.13e- 2
#>  5 <split [32/13]> Bootstrap0… <nls> k        37.8       2.68     14.1  9.01e-15
#>  6 <split [32/13]> Bootstrap0… <nls> b         6.73      1.17      5.75 2.78e- 6
#>  7 <split [32/11]> Bootstrap0… <nls> k        45.6       4.45     10.2  2.70e-11
#>  8 <split [32/11]> Bootstrap0… <nls> b         4.75      1.62      2.93 6.38e- 3
#>  9 <split [32/9]>  Bootstrap0… <nls> k        43.6       4.63      9.41 1.85e-10
#> 10 <split [32/9]>  Bootstrap0… <nls> b         5.89      1.68      3.51 1.44e- 3
#> # … with 3,992 more rows
```

## 신뢰구간

We can then calculate confidence intervals (using what is called the [percentile method](https://www.uvm.edu/~dhowell/StatPages/Randomization%20Tests/ResamplingWithR/BootstMeans/bootstrapping_means.html)):


```r
percentile_intervals <- int_pctl(boot_models, coef_info)
percentile_intervals
#> # A tibble: 2 × 6
#>   term   .lower .estimate .upper .alpha .method   
#>   <chr>   <dbl>     <dbl>  <dbl>  <dbl> <chr>     
#> 1 b      0.0475      4.12   7.31   0.05 percentile
#> 2 k     37.6        46.7   59.8    0.05 percentile
```

Or we can use histograms to get a more detailed idea of the uncertainty in each estimate:


```r
ggplot(boot_coefs, aes(estimate)) +
  geom_histogram(bins = 30) +
  facet_wrap( ~ term, scales = "free") +
  geom_vline(aes(xintercept = .lower), data = percentile_intervals, col = "blue") +
  geom_vline(aes(xintercept = .upper), data = percentile_intervals, col = "blue")
```

<img src="figs/unnamed-chunk-6-1.svg" width="672" />

The rsample package also has functions for [other types of confidence intervals](https://tidymodels.github.io/rsample/reference/int_pctl.html). 

## Possible model fits

We can use `augment()` to visualize the uncertainty in the fitted curve. Since there are so many bootstrap samples, we'll only show a sample of the model fits in our visualization:


```r
boot_aug <- 
  boot_models %>% 
  sample_n(200) %>% 
  mutate(augmented = map(model, augment)) %>% 
  unnest(augmented)

boot_aug
#> # A tibble: 6,400 × 8
#>    splits          id            model  coef_info       mpg    wt .fitted .resid
#>    <list>          <chr>         <list> <list>        <dbl> <dbl>   <dbl>  <dbl>
#>  1 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  16.4  4.07    15.6  0.829
#>  2 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  19.7  2.77    21.9 -2.21 
#>  3 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  19.2  3.84    16.4  2.84 
#>  4 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  21.4  2.78    21.8 -0.437
#>  5 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  26    2.14    27.8 -1.75 
#>  6 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  33.9  1.84    32.0  1.88 
#>  7 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  32.4  2.2     27.0  5.35 
#>  8 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  30.4  1.62    36.1 -5.70 
#>  9 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  21.5  2.46    24.4 -2.86 
#> 10 <split [32/11]> Bootstrap1644 <nls>  <tibble [2 ×…  26    2.14    27.8 -1.75 
#> # … with 6,390 more rows
```


```r
ggplot(boot_aug, aes(wt, mpg)) +
  geom_line(aes(y = .fitted, group = id), alpha = .2, col = "blue") +
  geom_point()
```

<img src="figs/unnamed-chunk-8-1.svg" width="672" />

With only a few small changes, we could easily perform bootstrapping with other kinds of predictive or hypothesis testing models, since the `tidy()` and `augment()` functions works for many statistical outputs. As another example, we could use `smooth.spline()`, which fits a cubic smoothing spline to data:


```r
fit_spline_on_bootstrap <- function(split) {
    data <- analysis(split)
    smooth.spline(data$wt, data$mpg, df = 4)
}

boot_splines <- 
  boots %>% 
  sample_n(200) %>% 
  mutate(spline = map(splits, fit_spline_on_bootstrap),
         aug_train = map(spline, augment))

splines_aug <- 
  boot_splines %>% 
  unnest(aug_train)

ggplot(splines_aug, aes(x, y)) +
  geom_line(aes(y = .fitted, group = id), alpha = 0.2, col = "blue") +
  geom_point()
```

<img src="figs/unnamed-chunk-9-1.svg" width="672" />



## Session information


```
#> ─ Session info  👧🏼  ⛱️  🇸🇷   ────────────────────────────────────────
#>  hash: girl: medium-light skin tone, umbrella on ground, flag: Suriname
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
#>  date     2022-01-11
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.10  2021-10-31 [1] CRAN (R 4.1.0)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
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
 
 
