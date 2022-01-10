---
title: "상관도와 회귀의 기초사항에 관한 타이디한 데이터 원칙"
tags: [broom]
categories: [statistical analysis]
type: learn-subsection
weight: 1
description: | 
  상관검정과 단순 회귀모델의 결과 분석을 여러 데이터셋에 대해 동시에 수행한다.
---





## 들어가기

이 장은 tidymodels 패키지만 필요로 합니다.

tidymodels 패키지인 [broom](https://broom.tidyverse.org/) 패키지가 단일 분석 결과를 일관성있는 형태로 요약하는데 유용하지만, 여러 분석결과를 합쳐야하는 high-throuput 을 위해 고안된 것입니다.
합쳐지는 것들은 데이터의 서브그룹, 다른 모델을 사용한 분석들, bootstrap replicates, permutations 등이 될 수 있습니다. 
특별이 이 패키지는 [tidyr](https://tidyr.tidyverse.org/) 의 `nest()/unnest()` 함수들, [purrr](https://purrr.tidyverse.org/) 의 `map()` 함수와 잘 작동합니다.

## 상관 분석

빌트인 데이터셋 `Orange` 으로 한번 살펴봅시다. 
`Orange` 를 `tibble` 로 강제변환하는 것부터 시작해봅시다. 
이렇게하면 더 나은 print 메소드를 제공하는데, 이는 나중에 리스트컬럼으로 작업하기 시작할 때 매우 유용하게 될 것입니다.


```r
library(tidymodels)

data(Orange)

Orange <- as_tibble(Orange)
Orange
#> # A tibble: 35 × 3
#>    Tree    age circumference
#>    <ord> <dbl>         <dbl>
#>  1 1       118            30
#>  2 1       484            58
#>  3 1       664            87
#>  4 1      1004           115
#>  5 1      1231           120
#>  6 1      1372           142
#>  7 1      1582           145
#>  8 2       118            33
#>  9 2       484            69
#> 10 2       664           111
#> # … with 25 more rows
```

35 개의 관측값들이 다음 3 개의 변수들을 가지고 있습니다: `Tree`, `age`, `circumference`. `Tree` 는 각각 다섯 나무를 의미하는 레벨 가진 팩터형입니다. 예상했듯이, 나이와 둘레길이는 상관관계가 있습니다:


```r
cor(Orange$age, Orange$circumference)
#> [1] 0.914

library(ggplot2)

ggplot(Orange, aes(age, circumference, color = Tree)) +
  geom_line()
```

<img src="figs/unnamed-chunk-2-1.svg" width="672" />

각 나무 *내(within)* 에서 개별적으로 상관관계가 있는지 테스트하고 싶다고 합시다. 
dplyr 의 `group_by` 로 할 수 있습니다:


```r
Orange %>% 
  group_by(Tree) %>%
  summarize(correlation = cor(age, circumference))
#> # A tibble: 5 × 2
#>   Tree  correlation
#>   <ord>       <dbl>
#> 1 3           0.988
#> 2 1           0.985
#> 3 5           0.988
#> 4 2           0.987
#> 5 4           0.984
```

(상관도가 취합본에서보다 훨씬 크다는 것과 상관도가 트리마다 비슷하다는 것을 주목하라). 

단순히 상관도를 추정하는 것보다 `cor.test()` 로 가설 검정을 해봅시다:


```r
ct <- cor.test(Orange$age, Orange$circumference)
ct
#> 
#> 	Pearson's product-moment correlation
#> 
#> data:  Orange$age and Orange$circumference
#> t = 13, df = 33, p-value = 2e-14
#> alternative hypothesis: true correlation is not equal to 0
#> 95 percent confidence interval:
#>  0.834 0.956
#> sample estimates:
#>   cor 
#> 0.914
```

이 테스트 출력에는 관심있는 값들이 많이 있습니다. p-value 와 추정값같이 길이 1 인 벡터도 있고, 신뢰구간과 같이 길이가 긴 것들도 있습니다. `tidy()` 함수를 사용하여 잘 정리된 티블로 만들 수 있습니다:


```r
tidy(ct)
#> # A tibble: 1 × 8
#>   estimate statistic  p.value parameter conf.low conf.high method    alternative
#>      <dbl>     <dbl>    <dbl>     <int>    <dbl>     <dbl> <chr>     <chr>      
#> 1    0.914      12.9 1.93e-14        33    0.834     0.956 Pearson'… two.sided
```

종종 우리는 데이터의 다른 부분들을 사용하여, 다중 테스트를 수행하거나 다중모델을 적합하는 경우가 있습니다. 이 경우, `nest-map-unnest` 워크플로를 추천합니다. 예를 들어, 각 다른 트리에 대해 상관도 검정을 수행하고 싶다고 해 봅시다. 관심있는 그룹에 기반하여 데이터를 `nest` (중첩) 하는 것부터 시작합니다:


```r
nested <- 
  Orange %>% 
  nest(data = c(age, circumference))
```

이제 `purrr::map()` 를 사용하여 각 중첩된 티블에 대해 상관검정을 수행합니다:


```r
nested %>% 
  mutate(test = map(data, ~ cor.test(.x$age, .x$circumference)))
#> # A tibble: 5 × 3
#>   Tree  data             test   
#>   <ord> <list>           <list> 
#> 1 1     <tibble [7 × 2]> <htest>
#> 2 2     <tibble [7 × 2]> <htest>
#> 3 3     <tibble [7 × 2]> <htest>
#> 4 4     <tibble [7 × 2]> <htest>
#> 5 5     <tibble [7 × 2]> <htest>
```

S3 객체의 리스트컬럼을 출력합니다.
`map()` 으로 각 객체들을 타이디하게 합니다.


```r
nested %>% 
  mutate(
    test = map(data, ~ cor.test(.x$age, .x$circumference)), # S3 list-col
    tidied = map(test, tidy)
  ) 
#> # A tibble: 5 × 4
#>   Tree  data             test    tidied          
#>   <ord> <list>           <list>  <list>          
#> 1 1     <tibble [7 × 2]> <htest> <tibble [1 × 8]>
#> 2 2     <tibble [7 × 2]> <htest> <tibble [1 × 8]>
#> 3 3     <tibble [7 × 2]> <htest> <tibble [1 × 8]>
#> 4 4     <tibble [7 × 2]> <htest> <tibble [1 × 8]>
#> 5 5     <tibble [7 × 2]> <htest> <tibble [1 × 8]>
```

마지막으로 타이디하게된 데이터프레임의 중첩을 풀어서 플랫티블로 볼 수 있게 합니다. 전체과정은 다음과 같게 됩니다: 


```r
Orange %>% 
  nest(data = c(age, circumference)) %>% 
  mutate(
    test = map(data, ~ cor.test(.x$age, .x$circumference)), # S3 list-col
    tidied = map(test, tidy)
  ) %>% 
  unnest(cols = tidied) %>% 
  select(-data, -test)
#> # A tibble: 5 × 9
#>   Tree  estimate statistic   p.value parameter conf.low conf.high method        
#>   <ord>    <dbl>     <dbl>     <dbl>     <int>    <dbl>     <dbl> <chr>         
#> 1 1        0.985      13.0 0.0000485         5    0.901     0.998 Pearson's pro…
#> 2 2        0.987      13.9 0.0000343         5    0.914     0.998 Pearson's pro…
#> 3 3        0.988      14.4 0.0000290         5    0.919     0.998 Pearson's pro…
#> 4 4        0.984      12.5 0.0000573         5    0.895     0.998 Pearson's pro…
#> 5 5        0.988      14.1 0.0000318         5    0.916     0.998 Pearson's pro…
#> # … with 1 more variable: alternative <chr>
```

## 회귀 모델

이런 유형의 워크플로는 회귀모델에 적용될 때 더 유용하게 됩니다. 타이디하지 않은 회귀결과는 다음과 같게 됩니다:


```r
lm_fit <- lm(age ~ circumference, data = Orange)
summary(lm_fit)
#> 
#> Call:
#> lm(formula = age ~ circumference, data = Orange)
#> 
#> Residuals:
#>    Min     1Q Median     3Q    Max 
#> -317.9 -140.9  -17.2   96.5  471.2 
#> 
#> Coefficients:
#>               Estimate Std. Error t value Pr(>|t|)    
#> (Intercept)     16.604     78.141    0.21     0.83    
#> circumference    7.816      0.606   12.90  1.9e-14 ***
#> ---
#> Signif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1
#> 
#> Residual standard error: 203 on 33 degrees of freedom
#> Multiple R-squared:  0.835,	Adjusted R-squared:  0.83 
#> F-statistic:  166 on 1 and 33 DF,  p-value: 1.93e-14
```

이 결과를 타이디하게 하면, 각 모델에 대해 출력이 여러 행이 됩니다:


```r
tidy(lm_fit)
#> # A tibble: 2 × 5
#>   term          estimate std.error statistic  p.value
#>   <chr>            <dbl>     <dbl>     <dbl>    <dbl>
#> 1 (Intercept)      16.6     78.1       0.212 8.33e- 1
#> 2 circumference     7.82     0.606    12.9   1.93e-14
```

이제 여러 회귀들을 정확히 전과 같은 워크플로를 사용하여 한번에 다룰 수 있습니다:


```r
Orange %>%
  nest(data = c(-Tree)) %>% 
  mutate(
    fit = map(data, ~ lm(age ~ circumference, data = .x)),
    tidied = map(fit, tidy)
  ) %>% 
  unnest(tidied) %>% 
  select(-data, -fit)
#> # A tibble: 10 × 6
#>    Tree  term          estimate std.error statistic   p.value
#>    <ord> <chr>            <dbl>     <dbl>     <dbl>     <dbl>
#>  1 1     (Intercept)    -265.      98.6      -2.68  0.0436   
#>  2 1     circumference    11.9      0.919    13.0   0.0000485
#>  3 2     (Intercept)    -132.      83.1      -1.59  0.172    
#>  4 2     circumference     7.80     0.560    13.9   0.0000343
#>  5 3     (Intercept)    -210.      85.3      -2.46  0.0574   
#>  6 3     circumference    12.0      0.835    14.4   0.0000290
#>  7 4     (Intercept)     -76.5     88.3      -0.867 0.426    
#>  8 4     circumference     7.17     0.572    12.5   0.0000573
#>  9 5     (Intercept)     -54.5     76.9      -0.709 0.510    
#> 10 5     circumference     8.79     0.621    14.1   0.0000318
```

여기 `mtcars` 데이터셋에서 보았듯이 회귀의 여러 설명변수를 쉽게 이용할 수 있습니다. 우리는 데이터를 자동변속 vs. 수동변속 (`am` 열) 으로 데이터를 중첩한 뒤 각 중첩된 티블 내에서 회귀를 수행합니다.


```r
data(mtcars)
mtcars <- as_tibble(mtcars)  # to play nicely with list-cols
mtcars
#> # A tibble: 32 × 11
#>      mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>    <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#>  1  21       6  160    110  3.9   2.62  16.5     0     1     4     4
#>  2  21       6  160    110  3.9   2.88  17.0     0     1     4     4
#>  3  22.8     4  108     93  3.85  2.32  18.6     1     1     4     1
#>  4  21.4     6  258    110  3.08  3.22  19.4     1     0     3     1
#>  5  18.7     8  360    175  3.15  3.44  17.0     0     0     3     2
#>  6  18.1     6  225    105  2.76  3.46  20.2     1     0     3     1
#>  7  14.3     8  360    245  3.21  3.57  15.8     0     0     3     4
#>  8  24.4     4  147.    62  3.69  3.19  20       1     0     4     2
#>  9  22.8     4  141.    95  3.92  3.15  22.9     1     0     4     2
#> 10  19.2     6  168.   123  3.92  3.44  18.3     1     0     4     4
#> # … with 22 more rows

mtcars %>%
  nest(data = c(-am)) %>% 
  mutate(
    fit = map(data, ~ lm(wt ~ mpg + qsec + gear, data = .x)),  # S3 list-col
    tidied = map(fit, tidy)
  ) %>% 
  unnest(tidied) %>% 
  select(-data, -fit)
#> # A tibble: 8 × 6
#>      am term        estimate std.error statistic  p.value
#>   <dbl> <chr>          <dbl>     <dbl>     <dbl>    <dbl>
#> 1     1 (Intercept)   4.28      3.46      1.24   0.247   
#> 2     1 mpg          -0.101     0.0294   -3.43   0.00750 
#> 3     1 qsec          0.0398    0.151     0.264  0.798   
#> 4     1 gear         -0.0229    0.349    -0.0656 0.949   
#> 5     0 (Intercept)   4.92      1.40      3.52   0.00309 
#> 6     0 mpg          -0.192     0.0443   -4.33   0.000591
#> 7     0 qsec          0.0919    0.0983    0.935  0.365   
#> 8     0 gear          0.147     0.368     0.398  0.696
```

우리가 만약 `tidy()` 출력 뿐만 아니라 `augment()` 와 `glance()` 출력까지 원하지만, 각 회귀를 한번만 수행하고 싶다면 어떻게 해야 할까요? 리스트컬럼을 이용하고 있기 때문에, 모델을 한번만 적합하고 다중 리스트열을 사용하여 타이디되고, glance 되고, augment 된 출력을 저장할 수 있습니다.


```r
regressions <- 
  mtcars %>%
  nest(data = c(-am)) %>% 
  mutate(
    fit = map(data, ~ lm(wt ~ mpg + qsec + gear, data = .x)),
    tidied = map(fit, tidy),
    glanced = map(fit, glance),
    augmented = map(fit, augment)
  )

regressions %>% 
  select(tidied) %>% 
  unnest(tidied)
#> # A tibble: 8 × 5
#>   term        estimate std.error statistic  p.value
#>   <chr>          <dbl>     <dbl>     <dbl>    <dbl>
#> 1 (Intercept)   4.28      3.46      1.24   0.247   
#> 2 mpg          -0.101     0.0294   -3.43   0.00750 
#> 3 qsec          0.0398    0.151     0.264  0.798   
#> 4 gear         -0.0229    0.349    -0.0656 0.949   
#> 5 (Intercept)   4.92      1.40      3.52   0.00309 
#> 6 mpg          -0.192     0.0443   -4.33   0.000591
#> 7 qsec          0.0919    0.0983    0.935  0.365   
#> 8 gear          0.147     0.368     0.398  0.696

regressions %>% 
  select(glanced) %>% 
  unnest(glanced)
#> # A tibble: 2 × 12
#>   r.squared adj.r.squared sigma statistic  p.value    df    logLik   AIC   BIC
#>       <dbl>         <dbl> <dbl>     <dbl>    <dbl> <dbl>     <dbl> <dbl> <dbl>
#> 1     0.833         0.778 0.291     15.0  0.000759     3  -0.00580  10.0  12.8
#> 2     0.625         0.550 0.522      8.32 0.00170      3 -12.4      34.7  39.4
#> # … with 3 more variables: deviance <dbl>, df.residual <int>, nobs <int>

regressions %>% 
  select(augmented) %>% 
  unnest(augmented)
#> # A tibble: 32 × 10
#>       wt   mpg  qsec  gear .fitted  .resid  .hat .sigma  .cooksd .std.resid
#>    <dbl> <dbl> <dbl> <dbl>   <dbl>   <dbl> <dbl>  <dbl>    <dbl>      <dbl>
#>  1  2.62  21    16.5     4    2.73 -0.107  0.517  0.304 0.0744      -0.527 
#>  2  2.88  21    17.0     4    2.75  0.126  0.273  0.304 0.0243       0.509 
#>  3  2.32  22.8  18.6     4    2.63 -0.310  0.312  0.279 0.188       -1.29  
#>  4  2.2   32.4  19.5     4    1.70  0.505  0.223  0.233 0.278        1.97  
#>  5  1.62  30.4  18.5     4    1.86 -0.244  0.269  0.292 0.0889      -0.982 
#>  6  1.84  33.9  19.9     4    1.56  0.274  0.286  0.286 0.125        1.12  
#>  7  1.94  27.3  18.9     4    2.19 -0.253  0.151  0.293 0.0394      -0.942 
#>  8  2.14  26    16.7     5    2.21 -0.0683 0.277  0.307 0.00732     -0.276 
#>  9  1.51  30.4  16.9     5    1.77 -0.259  0.430  0.284 0.263       -1.18  
#> 10  3.17  15.8  14.5     5    3.15  0.0193 0.292  0.308 0.000644     0.0789
#> # … with 22 more rows
```

모든그룹에 대한 추정값들과 p-value 들을 (출력 모델 객체들의 리스트 대신) 같은 타이디한 데이터프레임으로 결합함으로써, 새로운 클래스의 분석과 시각화가 직관적이게 됩니다. 다음을 포함합니다: 

- p-value 나 추정값으로 정렬하여 모든 테스트를 통틀어 가장 유의한 항을 찾음
- p-value 히스토그램
- p-value 를 effect size 추정값과 비교하는 volcano plots.

이들 케이스 각각에서, `terms` 열에 기반하여 쉽게 필터링, facet, 비교할 수 있습니다. 요약하면, 이전에는 타이디한 데이터 분석 도구들이 입력데이터에서만 사용할 수 있었는데, 데이터분석과 모델의 *결과*에도 사용할 수 있게 됩니다.

## 세션정보


```
#> ─ Session info  🤱🏻  🐭  👴🏽   ───────────────────────────────────────
#>  hash: breast-feeding: light skin tone, mouse face, old man: medium skin tone
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

