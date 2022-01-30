---
title: "모델 계수 작업하기"
tags: [parsnip,tune,broom,workflows]
categories: [model fitting]
type: learn-subsection
weight: 5
description: | 
  계수가 있는 모델을 생성하고, 적합된 모델에서 계수를 추출하고, 시각화한다.
---



## 들어가기 

통계 모델은 다양한 구조를 갖습니다.
어떤 모델은 각 항마다 계수(coefficient, weight)를 가지고 있습니다.
이러한 모델의 쉬운 예는 선형 혹은 로지스틱회귀이지만, 더 복잡한 모델 (예: 뉴럴네트워크, MARS)에도 모델 계수가 있습니다.
웨이트나 계수를 가진 모델으로 작업할 때 추정한 계수를 확인하고 싶은 경우가 많습니다.

이 장에서 tidymodels 를 사용하여 모델 적합 객체로 부터 계수 추정값을 추출하는 법에 대해 알아봅니다.
이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: glmnet and tidymodels.

## 선형 회귀

선형 회귀모델부터 시작해 봅시다:

`$$\hat{y} = \hat{\beta}_0 + \hat{\beta}_1x_1 + \ldots + \hat{\beta}_px_p$$` 

`\(\beta\)`는 계수이고 `\(x_j\)` 은 모델 설명변수 이거나 피쳐입니다.

[시카고 기차 데이터](https://bookdown.org/max/FES/chicago-intro.html) 에서 Clark 와 Lake 역의 승차를 세 역의 14일 이전 승차데이터를 이용하여 예측해 봅시다.

modeldata 패키지에 데이터가 있습니다:


```r
library(tidymodels)
tidymodels_prefer()
theme_set(theme_bw())

data(Chicago)

Chicago <- Chicago %>% select(ridership, Clark_Lake, Austin, Harlem)
```

### 단일 모델

단일한 parsnip 모델 객체를 적합하는 것부터 시작해 봅시다.
`linear_reg()` 를 하여 모델 specification 을 생성할 것입니다. 

{{% note %}} The default engine is `"lm"` so no call to `set_engine()` is required. {{%/ note %}}

공식과 데이터셋이 주어질 때, `fit()` 함수는 모델 계수를 추정합니다.


```r
lm_spec <- linear_reg()
lm_fit <- fit(lm_spec, ridership ~ ., data = Chicago)
lm_fit
#> parsnip model object
#> 
#> Fit time:  5ms 
#> 
#> Call:
#> stats::lm(formula = ridership ~ ., data = data)
#> 
#> Coefficients:
#> (Intercept)   Clark_Lake       Austin       Harlem  
#>       1.678        0.904        0.612       -0.555
```

`tidy()` 방법을 사용하는 것이 적합된 파라미터를 추출하는 가장 좋은 방법입니다.
broom 패키지에 있는 이 함수는 계수와, 연관된 통계량을 데이터프레임에 표준화된 열이름과 함께 반환합니다:


```r
tidy(lm_fit)
#> # A tibble: 4 × 5
#>   term        estimate std.error statistic   p.value
#>   <chr>          <dbl>     <dbl>     <dbl>     <dbl>
#> 1 (Intercept)    1.68     0.156      10.7  1.11e- 26
#> 2 Clark_Lake     0.904    0.0280     32.3  5.14e-210
#> 3 Austin         0.612    0.320       1.91 5.59e-  2
#> 4 Harlem        -0.555    0.165      -3.36 7.85e-  4
```

이후 섹션에서 이 함수를 사용합니다.

### 리샘플되거나 튜닝된 모델

tidymodels 프레임워크에서는 리샘플링 방법들로 모델 성능을 평가하는 것을 강조합니다. 
시게열 리샘플링 방법이 이 데이터에 적절하지만, 데이터를 리샘플하는 [bootstrap](https://www.tmwr.org/resampling.html#bootstrap) 방법을 이용할 수도 있습니다.
bootstrap 방법은 통계적 추정값의 불확실성을 평가할 때 표준적인 리샘플링 방법입니다.

플롯과 아웃풋을 단순화하기 위해 다섯 bootstrap 리샘플을 사용할 것입니다. (원래는 믿을만한 추정값을 위해서는 더 많은 개수의 리샘플을 사용합니다).


```r
set.seed(123)
bt <- bootstraps(Chicago, times = 5)
```

리샘플링이 만든 데이터셋의 다른 시뮬레이션 버전에 동일한 모델을 적합시킵니다. 
추천하는 방법은 tidymodels 함수 [`fit_resamples()`](https://www.tmwr.org/resampling.html#resampling-performance)를 사용하는 것입니다.

{{% warning %}} The `fit_resamples()` function does not automatically save the model objects for each resample since these can be quite large and its main purpose is estimating performance. However, we can pass a function to `fit_resamples()` that _can_ save the model object or any other aspect of the fit. {{%/ warning %}}

이 함수는 적합된 [워크플로우 객체](https://www.tmwr.org/workflows.html) 를 표현하는 인수를 입력으로 합니다. (`fit_resamples()` 에 워크플로우를 알려주지 않을지라도 그렇습니다.)

이제 모델 적합을 추출할 수 있습니다. 
모델 객체의 두 "레벨"을 볼 수 있습니다:

* parsnip 모델객체: 내부 모델객체를 래핑함. `extract_fit_parsnip()` 함수로 추출함. 

* `extract_fit_engine()` 를 통한 내부 모델객체 (aka 엔진적합). 

후자 옵션을 사용하여 이 모델객체를 이전섹션에서 했듯이 타이디하게 할 것입니다. 
이를 재사용할 수 있도록 컨트롤 함수에 추가합시다.


```r
get_lm_coefs <- function(x) {
  x %>% 
    # get the lm model object
    extract_fit_engine() %>% 
    # transform its format
    tidy()
}
tidy_ctrl <- control_grid(extract = get_lm_coefs)
```

이후 이 인수를 `fit_resamples()` 에 전달합니다:


```r
lm_res <- 
  lm_spec %>% 
  fit_resamples(ridership ~ ., resamples = bt, control = tidy_ctrl)
lm_res
#> # Resampling results
#> # Bootstrap sampling 
#> # A tibble: 5 × 5
#>   splits              id         .metrics         .notes           .extracts    
#>   <list>              <chr>      <list>           <list>           <list>       
#> 1 <split [5698/2076]> Bootstrap1 <tibble [2 × 4]> <tibble [0 × 1]> <tibble [1 ×…
#> 2 <split [5698/2098]> Bootstrap2 <tibble [2 × 4]> <tibble [0 × 1]> <tibble [1 ×…
#> 3 <split [5698/2064]> Bootstrap3 <tibble [2 × 4]> <tibble [0 × 1]> <tibble [1 ×…
#> 4 <split [5698/2082]> Bootstrap4 <tibble [2 × 4]> <tibble [0 × 1]> <tibble [1 ×…
#> 5 <split [5698/2088]> Bootstrap5 <tibble [2 × 4]> <tibble [0 × 1]> <tibble [1 ×…
```

리샘플링 결과에 `.extracts` 열이 생겼습니다.
이 객체에는 각 리샘플에 대한 `get_lm_coefs()` 아웃풋이 있습니다.
이 `.extracts` 열 구조는 조금 복잡합니다.
첫번째 요소 (첫번째 리샘플에 해당) 를 보는 것으로 시작합시다:


```r
lm_res$.extracts[[1]]
#> # A tibble: 1 × 2
#>   .extracts        .config             
#>   <list>           <chr>               
#> 1 <tibble [4 × 5]> Preprocessor1_Model1
```

이 요소에는 `tidy()` 함수 호출 결과를 가진 `.extracts` 이름의 _또다른_ 열이 있습니다:


```r
lm_res$.extracts[[1]]$.extracts[[1]]
#> # A tibble: 4 × 5
#>   term        estimate std.error statistic   p.value
#>   <chr>          <dbl>     <dbl>     <dbl>     <dbl>
#> 1 (Intercept)    1.40     0.157       8.90 7.23e- 19
#> 2 Clark_Lake     0.842    0.0280     30.1  2.39e-184
#> 3 Austin         1.46     0.320       4.54 5.70e-  6
#> 4 Harlem        -0.637    0.163      -3.92 9.01e-  5
```

이러한 중첩된 열들은 purrr `unnest()` 함수를 통해 flat 하게 만들수 있습니다: 


```r
lm_res %>% 
  select(id, .extracts) %>% 
  unnest(.extracts) 
#> # A tibble: 5 × 3
#>   id         .extracts        .config             
#>   <chr>      <list>           <chr>               
#> 1 Bootstrap1 <tibble [4 × 5]> Preprocessor1_Model1
#> 2 Bootstrap2 <tibble [4 × 5]> Preprocessor1_Model1
#> 3 Bootstrap3 <tibble [4 × 5]> Preprocessor1_Model1
#> 4 Bootstrap4 <tibble [4 × 5]> Preprocessor1_Model1
#> 5 Bootstrap5 <tibble [4 × 5]> Preprocessor1_Model1
```

중첩된 티블 열이 여전히 남아있기 때문에, 데이터를 유용한 포맷으로 만드는 같은 명령어를 다시 수행합니다:


```r
lm_coefs <- 
  lm_res %>% 
  select(id, .extracts) %>% 
  unnest(.extracts) %>% 
  unnest(.extracts)

lm_coefs %>% select(id, term, estimate, p.value)
#> # A tibble: 20 × 4
#>    id         term        estimate   p.value
#>    <chr>      <chr>          <dbl>     <dbl>
#>  1 Bootstrap1 (Intercept)    1.40  7.23e- 19
#>  2 Bootstrap1 Clark_Lake     0.842 2.39e-184
#>  3 Bootstrap1 Austin         1.46  5.70e-  6
#>  4 Bootstrap1 Harlem        -0.637 9.01e-  5
#>  5 Bootstrap2 (Intercept)    1.69  2.87e- 28
#>  6 Bootstrap2 Clark_Lake     0.911 1.06e-219
#>  7 Bootstrap2 Austin         0.595 5.93e-  2
#>  8 Bootstrap2 Harlem        -0.580 3.88e-  4
#>  9 Bootstrap3 (Intercept)    1.27  3.43e- 16
#> 10 Bootstrap3 Clark_Lake     0.859 5.03e-194
#> 11 Bootstrap3 Austin         1.09  6.77e-  4
#> 12 Bootstrap3 Harlem        -0.470 4.34e-  3
#> 13 Bootstrap4 (Intercept)    1.95  2.91e- 34
#> 14 Bootstrap4 Clark_Lake     0.974 1.47e-233
#> 15 Bootstrap4 Austin        -0.116 7.21e-  1
#> 16 Bootstrap4 Harlem        -0.620 2.11e-  4
#> 17 Bootstrap5 (Intercept)    1.87  1.98e- 33
#> 18 Bootstrap5 Clark_Lake     0.901 1.16e-210
#> 19 Bootstrap5 Austin         0.494 1.15e-  1
#> 20 Bootstrap5 Harlem        -0.512 1.73e-  3
```

더 나아졌습니다!
이제, 각 리샘플의 모델 계수를 플롯해봅시다.


```r
lm_coefs %>%
  filter(term != "(Intercept)") %>% 
  ggplot(aes(x = term, y = estimate, group = id, col = id)) +  
  geom_hline(yintercept = 0, lty = 3) + 
  geom_line(alpha = 0.3, lwd = 1.2) + 
  labs(y = "Coefficient", x = NULL) +
  theme(legend.position = "top")
```

<img src="figs/lm-plot-1.svg" width="672" />

Austin 역 데이터의 계수에 있어서 uncertainty 가 크고, 다른 두 역에 대해서는 작은 것 같이 보입니다.
결과를 unnest 하는 코드를 보면, double-nesting 구조가 과하거나 귀찮을 것입니다.
그러나, 추출 기능은 유연성이 있고, 더 간단한 구조로는 많은 use case 를 할 수 없었을 것입니다.

## 복잡한 모델: glmnet

glmnet 모델은 위에서 본 것과 같은 선형 회귀모형을 적합할 수 있습니다.
이 모델은 regulization (a.k.a penalization) 을 사용하여  모델 파라키터를 추정합니다.
이렇게 하면 계수를 0 으로 축소시키는데, 설명변수 사이에 상관성이 크거나, 변수 선택이 필요할 때 중요합니다. 
우리 Chiacago 열차데이터셋에 두 경우 다 해당합니다. 

이 모델이 사용하는 두 가지 유형의 penalization 이 있습니다:

* Lasso (a.k.a. `\(L_1\)`) 패널티는 절대값 0 이 될 정도로 모델 항을 축소시킬 수 있습니다 (즉, 해당 효과가 모델에서 완전히 제거됨). 

* Weight decay (a.k.a ridge 회귀 혹은 `\(L_2\)`) 는 상관성이 강한 설명변수들에 대해 가장 효과적인 유형의 패널티를 사용합니다. 

glmnet 모델은 두 가지의 튜닝파라미터가 있는데, penalization 전체 양과 두 패널티 유형의 mixture 입니다. 예를 들어, 이 specification 은:


```r
glmnet_spec <- 
  linear_reg(penalty = 0.1, mixture = 0.95) %>% 
  set_engine("glmnet")
```

95% lasso 와 5% weight decay 인 패널티를 가집니다. 이 두 패널티의 전체 양은 0.1 (상당히 높은 값) 입니다. 

{{% note %}} Models with regularization require that predictors are all on the same scale. The ridership at our three stations are very different, but glmnet [automatically centers and scales the data](https://parsnip.tidymodels.org/reference/details_linear_reg_glmnet.html). You can use recipes to [center and scale your data yourself](https://recipes.tidymodels.org/reference/step_normalize.html). {{%/ note %}}

모델 specification 과 모델 `workflow()` 의 공식을 결합한 뒤 모델을 데이터에 적합해 봅시다:


```r
glmnet_wflow <- 
  workflow() %>% 
  add_model(glmnet_spec) %>% 
  add_formula(ridership ~ .)

glmnet_fit <- fit(glmnet_wflow, Chicago)
glmnet_fit
#> ══ Workflow [trained] ════════════════════════════════════════════════
#> Preprocessor: Formula
#> Model: linear_reg()
#> 
#> ── Preprocessor ──────────────────────────────────────────────────────
#> ridership ~ .
#> 
#> ── Model ─────────────────────────────────────────────────────────────
#> 
#> Call:  glmnet::glmnet(x = maybe_matrix(x), y = y, family = "gaussian",      alpha = ~0.95) 
#> 
#>    Df %Dev Lambda
#> 1   0  0.0   6.10
#> 2   1 12.8   5.56
#> 3   1 23.4   5.07
#> 4   1 32.4   4.62
#> 5   1 40.0   4.21
#> 6   1 46.2   3.83
#> 7   1 51.5   3.49
#> 8   1 55.9   3.18
#> 9   1 59.6   2.90
#> 10  1 62.7   2.64
#> 11  2 65.3   2.41
#> 12  2 67.4   2.19
#> 13  2 69.2   2.00
#> 14  2 70.7   1.82
#> 15  2 72.0   1.66
#> 16  2 73.0   1.51
#> 17  2 73.9   1.38
#> 18  2 74.6   1.26
#> 19  2 75.2   1.14
#> 20  2 75.7   1.04
#> 21  2 76.1   0.95
#> 22  2 76.4   0.86
#> 23  2 76.7   0.79
#> 24  2 76.9   0.72
#> 25  2 77.1   0.66
#> 26  2 77.3   0.60
#> 27  2 77.4   0.54
#> 28  2 77.6   0.50
#> 29  2 77.6   0.45
#> 30  2 77.7   0.41
#> 31  2 77.8   0.38
#> 32  2 77.8   0.34
#> 33  2 77.9   0.31
#> 34  2 77.9   0.28
#> 35  2 78.0   0.26
#> 36  2 78.0   0.23
#> 37  2 78.0   0.21
#> 38  2 78.0   0.20
#> 39  2 78.0   0.18
#> 40  2 78.0   0.16
#> 41  2 78.0   0.15
#> 42  2 78.1   0.14
#> 43  2 78.1   0.12
#> 44  2 78.1   0.11
#> 45  2 78.1   0.10
#> 46  2 78.1   0.09
#> 
#> ...
#> and 9 more lines.
```

이 아웃풋에서, `lambda` 항은 패널티를 나타냅니다.

`penalty = 0.1` specification 에도 불구하고 아웃풋에서 패널티의 여러 값이 출력되었습니다. 패널티 값 "path" 에 적합하는 것입니다. 0.1 값에 관심이 있더라도, 같은 모델 객체의 여러 패널티 값에 대한 모델 계수를 얻을 수 있습니다.

계수를 구하는 두가지 다른 방법을 살펴봅시다. 두 방법 다 `tidy()` 방법을 사용합니다. 한 방법은 glmnet 객체를 타이디하게 하고 다른 방법은, tidymodels 객체를 타이디하게 할 것입니다.

### glmnet 패널티 값을 사용

이 glmnet fit 에는 데이터셋에 의존하는 여러 패널티 값이 있습니다;  
데이터(혹은 mixture 양)를 바꾸면 다른 패널티값이 산출됩니다. 
이 데이터셋에는, 55 개의 패널티가 있습니다. 
이 데이터셋에서 산출된 패널티를 구하기 위해, 엔진 fit 을 추출하고, 타이디하게 할 수 있습니다:


```r
glmnet_fit %>% 
  extract_fit_engine() %>% 
  tidy() %>% 
  rename(penalty = lambda) %>%   # <- for consistent naming
  filter(term != "(Intercept)")
#> # A tibble: 99 × 5
#>    term        step estimate penalty dev.ratio
#>    <chr>      <dbl>    <dbl>   <dbl>     <dbl>
#>  1 Clark_Lake     2   0.0753    5.56     0.127
#>  2 Clark_Lake     3   0.145     5.07     0.234
#>  3 Clark_Lake     4   0.208     4.62     0.324
#>  4 Clark_Lake     5   0.266     4.21     0.400
#>  5 Clark_Lake     6   0.319     3.83     0.463
#>  6 Clark_Lake     7   0.368     3.49     0.515
#>  7 Clark_Lake     8   0.413     3.18     0.559
#>  8 Clark_Lake     9   0.454     2.90     0.596
#>  9 Clark_Lake    10   0.491     2.64     0.627
#> 10 Clark_Lake    11   0.526     2.41     0.653
#> # … with 89 more rows
```

출력된 것을 보면, 잘 동작한 것 같지만, 우리 패널티 값 (0.1) 이 모델에서 산출한 목록에 없습니다!
내부 패키지에는 interpolation 을 이용하여, 이 구체적 값에 해당하는 계수를 산출하는 함수들이 있지만, glmnet 객체에 대한 `tidy()` 메소드는 이 함수들을 사용하지 않습니다. 

### 특정 패널티 값 사용하기

`tidy()` 메소드를 워크플로나 parsnip 객체에 실행한다면, 우리가 특정한 패널티 값에 해당하는 계수를 반환하는 다른 함수가 사용됩니다: 


```r
tidy(glmnet_fit)
#> # A tibble: 4 × 3
#>   term        estimate penalty
#>   <chr>          <dbl>   <dbl>
#> 1 (Intercept)    1.69      0.1
#> 2 Clark_Lake     0.846     0.1
#> 3 Austin         0.271     0.1
#> 4 Harlem         0         0.1
```

다른 (single) 패널티에 대해, 추가 인수를 사용할 수 있습니다:


```r
tidy(glmnet_fit, penalty = 5.5620)  # A value from above
#> # A tibble: 4 × 3
#>   term        estimate penalty
#>   <chr>          <dbl>   <dbl>
#> 1 (Intercept)  12.6       5.56
#> 2 Clark_Lake    0.0753    5.56
#> 3 Austin        0         5.56
#> 4 Harlem        0         5.56
```

두 개의 `tidy()` 메소드가 있는 이유는 tidymodels 에서의 주안점은 특정한 패널티 값에 있기 때문입니다. 


### glmnet 모델 튜닝하기

If we know a priori acceptable values for penalty and mixture, we can use the `fit_resamples()` function as we did before with linear regression. Otherwise, we can tune those parameters with the tidymodels `tune_*()` functions. 

Let's tune our glmnet model over both parameters with this grid: 


```r
pen_vals <- 10^seq(-3, 0, length.out = 10)
grid <- crossing(penalty = pen_vals, mixture = c(0.1, 1.0))
```

Here is where more glmnet-related complexity comes in: we know that each resample and each value of `mixture` will probably produce a different set of penalty values contained in the model object. _How can we look at the coefficients at the specific penalty values that we are using to tune?_

The approach that we suggest is to use the special `path_values` option for glmnet. Details are described in the [technical documentation about glmnet and tidymodels](https://parsnip.tidymodels.org/reference/glmnet-details.html#arguments) but in short, this parameter will assign the collection of penalty values used by each glmnet fit (regardless of the data or value of mixture). 

We can pass these as an engine argument and then update our previous workflow object:


```r
glmnet_tune_spec <- 
  linear_reg(penalty = tune(), mixture = tune()) %>% 
  set_engine("glmnet", path_values = pen_vals)

glmnet_wflow <- 
  glmnet_wflow %>% 
  update_model(glmnet_tune_spec)
```

Now we will use an extraction function similar to when we used ordinary least squares. We add an additional argument to retain coefficients that are shrunk to zero by the lasso penalty: 


```r
get_glmnet_coefs <- function(x) {
  x %>% 
    extract_fit_engine() %>% 
    tidy(return_zeros = TRUE) %>% 
    rename(penalty = lambda)
}
parsnip_ctrl <- control_grid(extract = get_glmnet_coefs)

glmnet_res <- 
  glmnet_wflow %>% 
  tune_grid(
    resamples = bt,
    grid = grid,
    control = parsnip_ctrl
  )
glmnet_res
#> # Tuning results
#> # Bootstrap sampling 
#> # A tibble: 5 × 5
#>   splits              id         .metrics          .notes           .extracts   
#>   <list>              <chr>      <list>            <list>           <list>      
#> 1 <split [5698/2076]> Bootstrap1 <tibble [40 × 6]> <tibble [0 × 1]> <tibble [20…
#> 2 <split [5698/2098]> Bootstrap2 <tibble [40 × 6]> <tibble [0 × 1]> <tibble [20…
#> 3 <split [5698/2064]> Bootstrap3 <tibble [40 × 6]> <tibble [0 × 1]> <tibble [20…
#> 4 <split [5698/2082]> Bootstrap4 <tibble [40 × 6]> <tibble [0 × 1]> <tibble [20…
#> 5 <split [5698/2088]> Bootstrap5 <tibble [40 × 6]> <tibble [0 × 1]> <tibble [20…
```

As noted before, the elements of the main `.extracts` column have an embedded list column with the results of `get_glmnet_coefs()`:  


```r
glmnet_res$.extracts[[1]] %>% head()
#> # A tibble: 6 × 4
#>   penalty mixture .extracts         .config              
#>     <dbl>   <dbl> <list>            <chr>                
#> 1       1     0.1 <tibble [40 × 5]> Preprocessor1_Model01
#> 2       1     0.1 <tibble [40 × 5]> Preprocessor1_Model02
#> 3       1     0.1 <tibble [40 × 5]> Preprocessor1_Model03
#> 4       1     0.1 <tibble [40 × 5]> Preprocessor1_Model04
#> 5       1     0.1 <tibble [40 × 5]> Preprocessor1_Model05
#> 6       1     0.1 <tibble [40 × 5]> Preprocessor1_Model06

glmnet_res$.extracts[[1]]$.extracts[[1]] %>% head()
#> # A tibble: 6 × 5
#>   term         step estimate penalty dev.ratio
#>   <chr>       <dbl>    <dbl>   <dbl>     <dbl>
#> 1 (Intercept)     1    0.568  1          0.769
#> 2 (Intercept)     2    0.432  0.464      0.775
#> 3 (Intercept)     3    0.607  0.215      0.779
#> 4 (Intercept)     4    0.846  0.1        0.781
#> 5 (Intercept)     5    1.06   0.0464     0.782
#> 6 (Intercept)     6    1.22   0.0215     0.783
```

As before, we'll have to use a double `unnest()`. Since the penalty value is in both the top-level and lower-level `.extracts`, we'll use `select()` to get rid of the first version (but keep `mixture`):


```r
glmnet_res %>% 
  select(id, .extracts) %>% 
  unnest(.extracts) %>% 
  select(id, mixture, .extracts) %>%  # <- removes the first penalty column
  unnest(.extracts)
```

But wait! We know that each glmnet fit contains all of the coefficients. This means, for a specific resample and value of `mixture`, the results are the same:  


```r
all.equal(
  # First bootstrap, first `mixture`, first `penalty`
  glmnet_res$.extracts[[1]]$.extracts[[1]],
  # First bootstrap, first `mixture`, second `penalty`
  glmnet_res$.extracts[[1]]$.extracts[[2]]
)
#> [1] TRUE
```

For this reason, we'll add a `slice(1)` when grouping by `id` and `mixture`. This will get rid of the replicated results. 


```r
glmnet_coefs <- 
  glmnet_res %>% 
  select(id, .extracts) %>% 
  unnest(.extracts) %>% 
  select(id, mixture, .extracts) %>% 
  group_by(id, mixture) %>%          # ┐
  slice(1) %>%                       # │ Remove the redundant results
  ungroup() %>%                      # ┘
  unnest(.extracts)

glmnet_coefs %>% 
  select(id, penalty, mixture, term, estimate) %>% 
  filter(term != "(Intercept)")
#> # A tibble: 300 × 5
#>    id         penalty mixture term       estimate
#>    <chr>        <dbl>   <dbl> <chr>         <dbl>
#>  1 Bootstrap1 1           0.1 Clark_Lake    0.391
#>  2 Bootstrap1 0.464       0.1 Clark_Lake    0.485
#>  3 Bootstrap1 0.215       0.1 Clark_Lake    0.590
#>  4 Bootstrap1 0.1         0.1 Clark_Lake    0.680
#>  5 Bootstrap1 0.0464      0.1 Clark_Lake    0.746
#>  6 Bootstrap1 0.0215      0.1 Clark_Lake    0.793
#>  7 Bootstrap1 0.01        0.1 Clark_Lake    0.817
#>  8 Bootstrap1 0.00464     0.1 Clark_Lake    0.828
#>  9 Bootstrap1 0.00215     0.1 Clark_Lake    0.834
#> 10 Bootstrap1 0.001       0.1 Clark_Lake    0.837
#> # … with 290 more rows
```

Now we have the coefficients. Let's look at how they behave as more regularization is used: 


```r
glmnet_coefs %>% 
  filter(term != "(Intercept)") %>% 
  mutate(mixture = format(mixture)) %>% 
  ggplot(aes(x = penalty, y = estimate, col = mixture, groups = id)) + 
  geom_hline(yintercept = 0, lty = 3) +
  geom_line(alpha = 0.5, lwd = 1.2) + 
  facet_wrap(~ term) + 
  scale_x_log10() +
  scale_color_brewer(palette = "Accent") +
  labs(y = "coefficient") +
  theme(legend.position = "top")
```

<img src="figs/glmnet-plot-1.svg" width="816" />

Notice a couple of things: 

* With a pure lasso model (i.e., `mixture = 1`), the Austin station predictor is selected out in each resample. With a mixture of both penalties, its influence increases. Also, as the penalty increases, the uncertainty in this coefficient decreases. 

* The Harlem predictor is either quickly selected out of the model or goes from negative to positive. 

## 세션정보


```
#> ─ Session info  🆎  👫🏼  🦙   ───────────────────────────────────────
#>  hash: AB button (blood type), woman and man holding hands: medium-light skin tone, llama
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
#>  date     2022-01-30
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  glmnet     * 4.1-3   2021-11-02 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
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
