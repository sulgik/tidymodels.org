---
title: "회귀 모델링의 두가지 방법"
tags: [rsample, parsnip]
categories: [model fitting]
type: learn-subsection
weight: 1
description: | 
  다른 연산엔진을 가진 다른 종류의 회귀 모형을 생성하고 훈련시키기.
---






## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: glmnet, randomForest, ranger, and tidymodels.

우리는 tidymodels 패키지 [parsnip](https://tidymodels.github.io/parsnip/) 로 회귀 모델을 생성하고 연속형이나 수치 값을 예측할 수 있습니다. 
여기에서, 모든 인풋이 수치형일 _필요가 없는_ 랜덤포레스트 모델 ([여기 ](https://bookdown.org/max/FES/categorical-trees.html)에서 이에 관한 논의를 살펴보라)을 우선 적합하고, _data descripters_ 뿐만 아니라, `fit()` 과 `fit_xy()` 를 사용하는 법을 논의해 봅시다.

두번째로는, regularized 선형 회귀 모형을 적합하여 parsnip 을 이용하여 다른 유형의 모델 사이를 움직여봅시다.

## Ames 주택 데이터

Ames 주택 데이터를 사용하여 parsnip 을 이용하여 회귀모형을 생성해 볼 것입니다. 첫째로, 데이터셋을 준비하고 간단한 트레이닝/테스트셋 분리를 합니다:


```r
library(tidymodels)

data(ames)

set.seed(4595)
data_split <- initial_split(ames, strata = "Sale_Price", prop = 0.75)

ames_train <- training(data_split)
ames_test  <- testing(data_split)
```

여기서 테스트셋을 사용하는 것은 _설명목적_ 입니다; 일반적으로 데이터 분석에서 이러한 테스트데이터는 저장된 후 다양한 모델을 평가한 후 맨 마지막에 사용됩니다.

## 랜덤 포레스트

랜덤포레스트를 파라미터 셋으로 적합하는 것부터 시작할 것입니다. 
`Longitude`, `Latitude`, `Lot_Area`, `Neighborhood`, and `Year_Sold` 개의 설명변수가 있는 모델을 생성합시다. 간단한 랜덤 포레스트 모델은 다음과 같이 설정할 수 있습니다:


```r
rf_defaults <- rand_forest(mode = "regression")
rf_defaults
#> Random Forest Model Specification (regression)
#> 
#> Computational engine: ranger
```

이 모델은 레인저 패키지 기본값으로 적합될 것입니다. `fit` 에 추가 인수를 넣지 않았기 때문에, _많은_ 인수들이 `ranger::ranger()` 함수로 부터 기본값으로 설정될 것입니다. 모델 함수의 도움말 페이지에서는 기본값 파라미터들을 기술하고 `translate()` 함수를 사용하여 이에 관한 세부사항을 확인할 수 있습니다. 

parsnip 패키지에는 모델을 적합하는 두가지 다른 인터페이스가 있습니다: 

- 공식(formula) 인터페이스 (`fit()`)
- 비공식 (non-formula) 인터페이스 (`fit_xy()`).

비공식 인터페이스부터 시작해봅니다:



```r
preds <- c("Longitude", "Latitude", "Lot_Area", "Neighborhood", "Year_Sold")

rf_xy_fit <- 
  rf_defaults %>%
  set_engine("ranger") %>%
  fit_xy(
    x = ames_train[, preds],
    y = log10(ames_train$Sale_Price)
  )

rf_xy_fit
#> parsnip model object
#> 
#> Fit time:  949ms 
#> Ranger result
#> 
#> Call:
#>  ranger::ranger(x = maybe_data_frame(x), y = y, num.threads = 1,      verbose = FALSE, seed = sample.int(10^5, 1)) 
#> 
#> Type:                             Regression 
#> Number of trees:                  500 
#> Sample size:                      2197 
#> Number of independent variables:  5 
#> Mtry:                             2 
#> Target node size:                 5 
#> Variable importance mode:         none 
#> Splitrule:                        variance 
#> OOB prediction error (MSE):       0.0085 
#> R squared (OOB):                  0.724
```

비공식 인터페이스는 설명변수를 모델 함수에 전달하기 전에 설명변수에는 아무 것도 하지 않습니다. 이 특별한 모델은 indicator 변수 (때로 "더미변수" 로 불림) 를 모델 적합 전에 생성할 필요가 _없습니다._ 출력에서 "Number of independent variables: 5" 를 나타냈습니다.

회귀 모델에서 우리는 기본 `predict()` 방법을 사용할 수 있는데, 이는 `.pred` 라고 명명된 하나의 열이 있는 티블을 반환합니다.


```r
test_results <- 
  ames_test %>%
  select(Sale_Price) %>%
  mutate(Sale_Price = log10(Sale_Price)) %>%
  bind_cols(
    predict(rf_xy_fit, new_data = ames_test[, preds])
  )
test_results %>% slice(1:5)
#> # A tibble: 5 × 2
#>   Sale_Price .pred
#>        <dbl> <dbl>
#> 1       5.39  5.25
#> 2       5.28  5.29
#> 3       5.23  5.26
#> 4       5.21  5.30
#> 5       5.60  5.51

# summarize performance
test_results %>% metrics(truth = Sale_Price, estimate = .pred) 
#> # A tibble: 3 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 rmse    standard      0.0945
#> 2 rsq     standard      0.733 
#> 3 mae     standard      0.0629
```

주의할 사항은: 

 * 모델이 indicator 변수들을 필요로 했다면, 이들을 `fit()` 을 사용하기 전에 수동으로 생성해야할 것입니다. (recipes 패키지를 사용하던지 해서)
 * 모델링 전에 출력을 수동으로 로그했어야 합니다.

이제 새로운 파라미터 값들을 사용하여 공식 방법을 사용하는 것을 배워봅시다:


```r
rand_forest(mode = "regression", mtry = 3, trees = 1000) %>%
  set_engine("ranger") %>%
  fit(
    log10(Sale_Price) ~ Longitude + Latitude + Lot_Area + Neighborhood + Year_Sold,
    data = ames_train
  )
#> parsnip model object
#> 
#> Fit time:  2.6s 
#> Ranger result
#> 
#> Call:
#>  ranger::ranger(x = maybe_data_frame(x), y = y, mtry = min_cols(~3,      x), num.trees = ~1000, num.threads = 1, verbose = FALSE,      seed = sample.int(10^5, 1)) 
#> 
#> Type:                             Regression 
#> Number of trees:                  1000 
#> Sample size:                      2197 
#> Number of independent variables:  5 
#> Mtry:                             3 
#> Target node size:                 5 
#> Variable importance mode:         none 
#> Splitrule:                        variance 
#> OOB prediction error (MSE):       0.0084 
#> R squared (OOB):                  0.727
```
 

ranger 대신 randomForest 패키지를 사용하고 싶다고 가정해 봅시다. 
공식에서 바뀌어야 하는 유일한 부분은 `set_engine()` 인수입니다:



```r
rand_forest(mode = "regression", mtry = 3, trees = 1000) %>%
  set_engine("randomForest") %>%
  fit(
    log10(Sale_Price) ~ Longitude + Latitude + Lot_Area + Neighborhood + Year_Sold,
    data = ames_train
  )
#> parsnip model object
#> 
#> Fit time:  7.5s 
#> 
#> Call:
#>  randomForest(x = maybe_data_frame(x), y = y, ntree = ~1000, mtry = min_cols(~3,      x)) 
#>                Type of random forest: regression
#>                      Number of trees: 1000
#> No. of variables tried at each split: 3
#> 
#>           Mean of squared residuals: 0.00847
#>                     % Var explained: 72.5
```

프린트된 공식 코드 를 살펴봅시다; 첫번째 함수는 인수 이름 `ntree` 를 사용하고, 다른 함수는 `num.trees` 를 사용합니다. parsnip 모델들은 주 인수의 구체적인 이름들을 몰라도 됩니다. 

`mtry` 값을 데이터의 설명변수의 개수에 기반하여 수정하고 싶다고 가정합니다. 일반적으로, 좋은 기본값은 `floor(sqrt(num_predictors))` 이지만, 순수한 배깅 모델은 `mtry` 값이 파라미터 전체 숫자와 같기를 요구합니다. 모델이 적합될 때 얼마나 많은 설명변수가 있을 것인지 알 수 없는 경우가 있어서, 코드를 작성하기 전에 정확히 아는 것은 여러울 수 있습니다.


parsnip 이 모델을 적합할 때, [_data descriptors_](https://tidymodels.github.io/parsnip/reference/descriptors.html) 를 사용할 수 있게 됩니다. 이것들은 모델이 적합될 때 어떤 것을 사용할 수 잇는지 알려주려고 합니다. 모델 객체가 생성될 때 (예를 들어 `rand_forest()` 를 사용해서) 제공하는 인수 값들을 delay 하지 않는다면 _즉시 평가됩니다_. 인수평가를 지연시키기 위해서는, `rlang:expr()` 를 사용하여 표현형(expression)을 만들 수 있습니다.

우리 예제 모델이서 관련된 두 개의 데이터 descriptor 는:

 * `.preds()`: **더미변수 생성 이전의** 설명변수와 관련있는 데이터셋 내의 설명 _변수_ 의 개수.
 * `.cols()`: 더미 변수들 (혹은 기타 인코딩)이 생성된 후 설명변수 _열_의 개수.

ranger 는 indicator 값을 생성하지 않기 때문에, `.preds()` 는 배깅모델의 `mtry` 에 적절할 것입니다.

`.preds()` descriptor 가 있는 표현형을 사용하여 배깅 모델을 적합해 봅시다.


```r
rand_forest(mode = "regression", mtry = .preds(), trees = 1000) %>%
  set_engine("ranger") %>%
  fit(
    log10(Sale_Price) ~ Longitude + Latitude + Lot_Area + Neighborhood + Year_Sold,
    data = ames_train
  )
#> parsnip model object
#> 
#> Fit time:  3.6s 
#> Ranger result
#> 
#> Call:
#>  ranger::ranger(x = maybe_data_frame(x), y = y, mtry = min_cols(~.preds(),      x), num.trees = ~1000, num.threads = 1, verbose = FALSE,      seed = sample.int(10^5, 1)) 
#> 
#> Type:                             Regression 
#> Number of trees:                  1000 
#> Sample size:                      2197 
#> Number of independent variables:  5 
#> Mtry:                             5 
#> Target node size:                 5 
#> Variable importance mode:         none 
#> Splitrule:                        variance 
#> OOB prediction error (MSE):       0.00867 
#> R squared (OOB):                  0.718
```


## Regularized 회귀

선형 모델도 이 데이터셋에 잘 맞아 들어갈 것입니다. 
`linear_reg()` parsnip 모델을 사용할 수 있습니다.
regularization/penalization 을 수행할 수 있는 두 개의 엔진, glmnet 과 sparklyr 패키지가 있습니다. 
전자를 사용해 봅시다. 
glmnet 패키지는 비공식(non-formula) 방법만 구현하지만 parsnip 은 공식, 비공식 방법 모두 사용할 수 있게 합니다. 

regularization 이 사용될 때, 설명변수는 모델에 전달되기 전, 우선 센터링되고 스케일링 되어야 합니다. 공식 방법은 자동으로 이를 수행해주지 않으므로, 직접 해야합니다. 이러한 단계를 위해 [recipes](https://tidymodels.github.io/recipes/) 패키지를 사용할 것입니다.


```r
norm_recipe <- 
  recipe(
    Sale_Price ~ Longitude + Latitude + Lot_Area + Neighborhood + Year_Sold, 
    data = ames_train
  ) %>%
  step_other(Neighborhood) %>% 
  step_dummy(all_nominal()) %>%
  step_center(all_predictors()) %>%
  step_scale(all_predictors()) %>%
  step_log(Sale_Price, base = 10) %>% 
  # estimate the means and standard deviations
  prep(training = ames_train, retain = TRUE)

# Now let's fit the model using the processed version of the data

glmn_fit <- 
  linear_reg(penalty = 0.001, mixture = 0.5) %>% 
  set_engine("glmnet") %>%
  fit(Sale_Price ~ ., data = bake(norm_recipe, new_data = NULL))
glmn_fit
#> parsnip model object
#> 
#> Fit time:  10ms 
#> 
#> Call:  glmnet::glmnet(x = maybe_matrix(x), y = y, family = "gaussian",      alpha = ~0.5) 
#> 
#>    Df %Dev Lambda
#> 1   0  0.0 0.1380
#> 2   1  2.0 0.1260
#> 3   1  3.7 0.1150
#> 4   1  5.3 0.1050
#> 5   2  7.1 0.0953
#> 6   3  9.6 0.0869
#> 7   4 12.6 0.0791
#> 8   5 15.4 0.0721
#> 9   5 17.9 0.0657
#> 10  7 20.8 0.0599
#> 11  7 23.5 0.0545
#> 12  7 25.8 0.0497
#> 13  8 28.2 0.0453
#> 14  8 30.3 0.0413
#> 15  8 32.1 0.0376
#> 16  8 33.7 0.0343
#> 17  8 35.0 0.0312
#> 18  8 36.1 0.0284
#> 19  8 37.0 0.0259
#> 20  9 37.9 0.0236
#> 21  9 38.6 0.0215
#> 22  9 39.3 0.0196
#> 23  9 39.8 0.0179
#> 24  9 40.3 0.0163
#> 25 10 40.7 0.0148
#> 26 11 41.1 0.0135
#> 27 11 41.4 0.0123
#> 28 11 41.6 0.0112
#> 29 11 41.9 0.0102
#> 30 12 42.1 0.0093
#> 31 12 42.3 0.0085
#> 32 12 42.4 0.0077
#> 33 12 42.6 0.0070
#> 34 12 42.7 0.0064
#> 35 12 42.8 0.0059
#> 36 12 42.8 0.0053
#> 37 12 42.9 0.0049
#> 38 12 43.0 0.0044
#> 39 12 43.0 0.0040
#> 40 12 43.0 0.0037
#> 41 12 43.1 0.0034
#> 42 12 43.1 0.0031
#> 43 12 43.1 0.0028
#> 44 12 43.1 0.0025
#> 45 12 43.1 0.0023
#> 46 12 43.2 0.0021
#> 47 12 43.2 0.0019
#> 48 12 43.2 0.0018
#> 49 12 43.2 0.0016
#> 50 12 43.2 0.0014
#> 51 12 43.2 0.0013
#> 52 12 43.2 0.0012
#> 53 12 43.2 0.0011
#> 54 12 43.2 0.0010
#> 55 12 43.2 0.0009
#> 56 12 43.2 0.0008
#> 57 12 43.2 0.0008
#> 58 12 43.2 0.0007
#> 59 12 43.2 0.0006
#> 60 12 43.2 0.0006
#> 61 12 43.2 0.0005
#> 62 12 43.2 0.0005
#> 63 12 43.2 0.0004
#> 64 12 43.2 0.0004
#> 65 12 43.2 0.0004
```

`penalty` 가 설정되지 않으면 모든 `lambda` 값이 계산될 것입니다. 
특정 `lambda` (aka `penalty`) 값에 대한 예측값을 얻으려면:


```r
# First, get the processed version of the test set predictors:
test_normalized <- bake(norm_recipe, new_data = ames_test, all_predictors())

test_results <- 
  test_results %>%
  rename(`random forest` = .pred) %>%
  bind_cols(
    predict(glmn_fit, new_data = test_normalized) %>%
      rename(glmnet = .pred)
  )
test_results
#> # A tibble: 733 × 3
#>    Sale_Price `random forest` glmnet
#>         <dbl>           <dbl>  <dbl>
#>  1       5.39            5.25   5.16
#>  2       5.28            5.29   5.27
#>  3       5.23            5.26   5.24
#>  4       5.21            5.30   5.24
#>  5       5.60            5.51   5.24
#>  6       5.32            5.29   5.26
#>  7       5.17            5.14   5.18
#>  8       5.06            5.13   5.17
#>  9       4.98            5.01   5.18
#> 10       5.11            5.14   5.19
#> # … with 723 more rows

test_results %>% metrics(truth = Sale_Price, estimate = glmnet) 
#> # A tibble: 3 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 rmse    standard      0.142 
#> 2 rsq     standard      0.391 
#> 3 mae     standard      0.0979

test_results %>% 
  gather(model, prediction, -Sale_Price) %>% 
  ggplot(aes(x = prediction, y = Sale_Price)) + 
  geom_abline(col = "green", lty = 2) + 
  geom_point(alpha = .4) + 
  facet_wrap(~model) + 
  coord_fixed()
```

<img src="figs/glmn-pred-1.svg" width="672" />

마지막 플롯에서 랜덤포레스트와 regularized 회귀모델의 성능을 비교합니다.

## 세션정보


```
#> ─ Session info  👩🏼‍🦰  🚄  🤙🏻   ───────────────────────────────────────
#>  hash: woman: medium-light skin tone, red hair, high-speed train, call me hand: light skin tone
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
#>  date     2022-01-13
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package      * version date (UTC) lib source
#>  broom        * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials        * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr        * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2      * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  glmnet       * 4.1-3   2021-11-02 [1] CRAN (R 4.1.0)
#>  infer        * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  parsnip      * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr        * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  randomForest * 4.6-14  2018-03-25 [1] CRAN (R 4.1.0)
#>  ranger       * 0.13.1  2021-07-14 [1] CRAN (R 4.1.0)
#>  recipes      * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang          0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
#>  rsample      * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  tibble       * 3.1.6   2021-11-07 [1] CRAN (R 4.1.0)
#>  tidymodels   * 0.1.4   2021-10-01 [1] CRAN (R 4.1.0)
#>  tune         * 0.1.6   2021-07-21 [1] CRAN (R 4.1.0)
#>  workflows    * 0.2.4   2021-10-12 [1] CRAN (R 4.1.0)
#>  yardstick    * 0.0.9   2021-11-22 [1] CRAN (R 4.1.0)
#> 
#>  [1] /Library/Frameworks/R.framework/Versions/4.1/Resources/library
#> 
#> ────────────────────────────────────────────────────────────────────
```
 
