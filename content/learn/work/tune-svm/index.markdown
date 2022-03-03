---
title: "그리드서치로 모델 튜닝하기"
tags: [rsample, parsnip, tune, yardstick]
categories: [model tuning]
type: learn-subsection
weight: 1
description: | 
  그리드에서 훈련하여 하이퍼파라미터 선택하기
---


  


## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: kernlab, mlbench, and tidymodels.

이 장에서는 그리드서치를 사용하여 모델을 튜닝하는 방법을 시연합니다.
모델을 훈련할 때 하나의 데이터셋에서 직접 학습할 수 없는 **하이퍼파라미터** 가 많이 있습니다.
가능한 하이퍼파라미터 값들로 이루어진 그리드에서 모델을 여러번 훈편하고 가장 좋은 것을 발견할 수 있습니다.

## 예제 데이터

모델 튜닝을 시연하기 위해, mlbench 패키지의 Ionosphere 데이터를 사용할 수 있습니다:


```r
library(tidymodels)
library(mlbench)
data(Ionosphere)
```

`?Ionosphere` 를 하면:

> 이 레이더 데이터는 Labrador, Goose Bay 의 시스템에서 수집되었다. 이 시스템은 6.4 킬로와트 수준의 transmitted power 가 있는 16개의 고주파 안테나의 phased array 로 이루어져 있다. 자세한 내용은 논문을 살펴보라. 목표는 ionosphere 의 자유 전자였다. "좋은" 레이더는 ionosphere 의 어떤 유형의 구조 증거를 보여주는 것을 반환한다. "나쁜" 레이더는 그렇지 않은 것을 반환한다; 신호가 ionosphere 를 투과한다.

> 펄스 시간과 펄스 숫자를 인수로 가지는 autocorrelation 함수를 사용하여 수신된 신호가 처리되었다. Goose Bay 시스템에는 17 펄스 숫자가 있었다. 이 데이터베이스의 인스턴스들은 펄스 숫자당 2 개의 attribute 가 기술하는데, 복잡한 전자기 신호에서 나오는 함수가 반환하는 complex value 에 해당한다. 

43 개의 설명변수와 팩터형 아웃컴이 있습니다. 
설명변수 두 개는 팩터형이고  (`V1`, `V2`), 나머지는 -1 에서 1 의 범위로 스케일된 수치형 변수입니다.
두 개의 팩터형 설명변수는 희소 분포를 가집니다:


```r
table(Ionosphere$V1)
#> 
#>   0   1 
#>  38 313
table(Ionosphere$V2)
#> 
#>   0 
#> 351
```

`V2` 는 0-분산 설명변수이므로 이를 모델에 넣는 것은 의미가 없습니다.
`V1` 도 0-분산은 아니지만, resampling 과정에서 같은 값이 모두 뽑힌다면 그럴 _가능성이 있습니다_.
이것이 이슈일까요?
표준 R 공식 인프라는 관측값이 하나만 있다면 에러가 납니다:


```r
glm(Class ~ ., data = Ionosphere, family = binomial)
#> Error in `contrasts<-`(`*tmp*`, value = contr.funs[1 + isOF[nn]]): contrasts can be applied only to factors with 2 or more levels

# Surprisingly, this doesn't help: 

glm(Class ~ . - V2, data = Ionosphere, family = binomial)
#> Error in `contrasts<-`(`*tmp*`, value = contr.funs[1 + isOF[nn]]): contrasts can be applied only to factors with 2 or more levels
```

문제가 있는 두 개의 변수들을 제거해 봅시다:


```r
Ionosphere <- Ionosphere %>% select(-V1, -V2)
```

## 서치 인풋

radial basis 함수 서포트벡터머신을 이 데이터에 적합하고 SVM 코스트 파라미터와 커널 함수에서 `\(\sigma\)` 파라미터를 튠할 것입니다:


```r
svm_mod <-
  svm_rbf(cost = tune(), rbf_sigma = tune()) %>%
  set_mode("classification") %>%
  set_engine("kernlab")
```

이 장에서, 다음을 사용하여 튜닝을 두 가지 방법으로 보여줄 것입니다:

- 표준 R 공식 
- 레시피

간단한 레시피를 생성해 봅시다:


```r
iono_rec <-
  recipe(Class ~ ., data = Ionosphere)  %>%
  # remove any zero variance predictors
  step_zv(all_predictors()) %>% 
  # remove any linear combinations
  step_lincomb(all_numeric())
```

마지막으로 튜닝에 필요한 것은 rsample 객체로 정의할 수 있는 resampling 전략입니다. 
기초 부트스트래핑을 이용하는 것을 해봅시다:


```r
set.seed(4943)
iono_rs <- bootstraps(Ionosphere, times = 30)
```


## 선택적 인풋

모델 튜닝에서 _선택적_ 단계는 out-of-sample 예측을 사용하여 계산해야하는 메트릭을 명시하는 것입니다.
분류에서, 기본값은 log-likelihood 통계량과 종합 정확도를 계산하는 것입니다.
기본값 대신, AUROC 를 사용할 것입니다.
yardstick 패키지에 있는 함수를 사용하여 메트릭들을 생성할 수 있습니다:


```r
roc_vals <- metric_set(roc_auc)
```

그리드나 파라미터가 없다면, space-filling 디자인(라틴 방격법을 통한)을 이용하여 10 개의 하이퍼파라미터 세트가 생성됩니다.
그리드는 파라미터들이 열에 있고, 파라미터 조합이 행에 있는 데이터프레임으로 제공할 수 있습니다.
여기에, 기본값이 사용될 것입니다.

또한, 서치의 다른 면을 명시하는 컨트롤 객체를 전달할 수도 있습니다.
여기에, verbose 옵션은 껐고, out-of-sample 예측을 저장하는 옵션은 켰습니다.


```r
ctrl <- control_grid(verbose = FALSE, save_pred = TRUE)
```

## 공식으로 실행하기

첫번째로, 공식 인터페이스를 사용할 수 있습니다:


```r
set.seed(35)
formula_res <-
  svm_mod %>% 
  tune_grid(
    Class ~ .,
    resamples = iono_rs,
    metrics = roc_vals,
    control = ctrl
  )
formula_res
#> # Tuning results
#> # Bootstrap sampling 
#> # A tibble: 30 × 5
#>    splits            id          .metrics          .notes           .predictions
#>    <list>            <chr>       <list>            <list>           <list>      
#>  1 <split [351/120]> Bootstrap01 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  2 <split [351/130]> Bootstrap02 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  3 <split [351/137]> Bootstrap03 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  4 <split [351/141]> Bootstrap04 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  5 <split [351/131]> Bootstrap05 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  6 <split [351/131]> Bootstrap06 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  7 <split [351/127]> Bootstrap07 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  8 <split [351/123]> Bootstrap08 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  9 <split [351/131]> Bootstrap09 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#> 10 <split [351/117]> Bootstrap10 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#> # … with 20 more rows
```

`.metrics` 열에는 각 튜닝 파라미터 조합의 성능 지표 티블이 있습니다:


```r
formula_res %>% 
  select(.metrics) %>% 
  slice(1) %>% 
  pull(1)
#> [[1]]
#> # A tibble: 10 × 6
#>        cost rbf_sigma .metric .estimator .estimate .config              
#>       <dbl>     <dbl> <chr>   <chr>          <dbl> <chr>                
#>  1  0.00849  1.11e-10 roc_auc binary         0.815 Preprocessor1_Model01
#>  2  0.176    7.28e- 8 roc_auc binary         0.839 Preprocessor1_Model02
#>  3 14.9      3.93e- 4 roc_auc binary         0.870 Preprocessor1_Model03
#>  4  5.51     2.10e- 3 roc_auc binary         0.919 Preprocessor1_Model04
#>  5  1.87     3.53e- 7 roc_auc binary         0.838 Preprocessor1_Model05
#>  6  0.00719  1.45e- 5 roc_auc binary         0.832 Preprocessor1_Model06
#>  7  0.00114  8.41e- 2 roc_auc binary         0.969 Preprocessor1_Model07
#>  8  0.950    1.74e- 1 roc_auc binary         0.984 Preprocessor1_Model08
#>  9  0.189    3.13e- 6 roc_auc binary         0.832 Preprocessor1_Model09
#> 10  0.0364   4.96e- 9 roc_auc binary         0.839 Preprocessor1_Model10
```

최종 리샘플링 추정값을 얻기 위해, `collect_metrics()` 함수를 그리드 객체에 사용할 수 있습니다:


```r
estimates <- collect_metrics(formula_res)
estimates
#> # A tibble: 10 × 8
#>        cost rbf_sigma .metric .estimator  mean     n std_err .config            
#>       <dbl>     <dbl> <chr>   <chr>      <dbl> <int>   <dbl> <chr>              
#>  1  0.00849  1.11e-10 roc_auc binary     0.822    30 0.00718 Preprocessor1_Mode…
#>  2  0.176    7.28e- 8 roc_auc binary     0.871    30 0.00525 Preprocessor1_Mode…
#>  3 14.9      3.93e- 4 roc_auc binary     0.916    30 0.00497 Preprocessor1_Mode…
#>  4  5.51     2.10e- 3 roc_auc binary     0.960    30 0.00378 Preprocessor1_Mode…
#>  5  1.87     3.53e- 7 roc_auc binary     0.871    30 0.00524 Preprocessor1_Mode…
#>  6  0.00719  1.45e- 5 roc_auc binary     0.871    30 0.00534 Preprocessor1_Mode…
#>  7  0.00114  8.41e- 2 roc_auc binary     0.966    30 0.00301 Preprocessor1_Mode…
#>  8  0.950    1.74e- 1 roc_auc binary     0.979    30 0.00204 Preprocessor1_Mode…
#>  9  0.189    3.13e- 6 roc_auc binary     0.871    30 0.00536 Preprocessor1_Mode…
#> 10  0.0364   4.96e- 9 roc_auc binary     0.871    30 0.00537 Preprocessor1_Mode…
```

가장 좋은 조합은:


```r
show_best(formula_res, metric = "roc_auc")
#> # A tibble: 5 × 8
#>       cost rbf_sigma .metric .estimator  mean     n std_err .config             
#>      <dbl>     <dbl> <chr>   <chr>      <dbl> <int>   <dbl> <chr>               
#> 1  0.950   0.174     roc_auc binary     0.979    30 0.00204 Preprocessor1_Model…
#> 2  0.00114 0.0841    roc_auc binary     0.966    30 0.00301 Preprocessor1_Model…
#> 3  5.51    0.00210   roc_auc binary     0.960    30 0.00378 Preprocessor1_Model…
#> 4 14.9     0.000393  roc_auc binary     0.916    30 0.00497 Preprocessor1_Model…
#> 5  0.00719 0.0000145 roc_auc binary     0.871    30 0.00534 Preprocessor1_Model…
```

##  레시피로 실행하기

다음으로, 문법은 같지만, 전처리 인수로 *레시피*를 전달할 수 있습니다:


```r
set.seed(325)
recipe_res <-
  svm_mod %>% 
  tune_grid(
    iono_rec,
    resamples = iono_rs,
    metrics = roc_vals,
    control = ctrl
  )
recipe_res
#> # Tuning results
#> # Bootstrap sampling 
#> # A tibble: 30 × 5
#>    splits            id          .metrics          .notes           .predictions
#>    <list>            <chr>       <list>            <list>           <list>      
#>  1 <split [351/120]> Bootstrap01 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  2 <split [351/130]> Bootstrap02 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  3 <split [351/137]> Bootstrap03 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  4 <split [351/141]> Bootstrap04 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  5 <split [351/131]> Bootstrap05 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  6 <split [351/131]> Bootstrap06 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  7 <split [351/127]> Bootstrap07 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  8 <split [351/123]> Bootstrap08 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#>  9 <split [351/131]> Bootstrap09 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#> 10 <split [351/117]> Bootstrap10 <tibble [10 × 6]> <tibble [0 × 1]> <tibble [1,…
#> # … with 20 more rows
```

여기서 가장 좋은 설정은:


```r
show_best(recipe_res, metric = "roc_auc")
#> # A tibble: 5 × 8
#>      cost rbf_sigma .metric .estimator  mean     n std_err .config              
#>     <dbl>     <dbl> <chr>   <chr>      <dbl> <int>   <dbl> <chr>                
#> 1 15.6    0.182     roc_auc binary     0.981    30 0.00213 Preprocessor1_Model04
#> 2  0.385  0.0276    roc_auc binary     0.978    30 0.00222 Preprocessor1_Model03
#> 3  0.143  0.00243   roc_auc binary     0.930    30 0.00443 Preprocessor1_Model06
#> 4  0.841  0.000691  roc_auc binary     0.892    30 0.00504 Preprocessor1_Model07
#> 5  0.0499 0.0000335 roc_auc binary     0.872    30 0.00521 Preprocessor1_Model08
```

## Out-of-sample 예측

`save_pred = TRUE` 를 해서 튜닝하는 동안 각 리샘플에 대해 out-of-sample 예측값들을 저장하면, `collect_predictions()` 을 사용하여 이러한 예측값들을 튜닝 파라미터와 리샘플 식별자와 함께 얻을 수 있습니다:


```r
collect_predictions(recipe_res)
#> # A tibble: 38,740 × 8
#>    id          .pred_bad .pred_good  .row    cost  rbf_sigma Class .config      
#>    <chr>           <dbl>      <dbl> <int>   <dbl>      <dbl> <fct> <chr>        
#>  1 Bootstrap01     0.333      0.667     1 0.00296 0.00000383 good  Preprocessor…
#>  2 Bootstrap01     0.333      0.667     9 0.00296 0.00000383 good  Preprocessor…
#>  3 Bootstrap01     0.333      0.667    10 0.00296 0.00000383 bad   Preprocessor…
#>  4 Bootstrap01     0.333      0.667    12 0.00296 0.00000383 bad   Preprocessor…
#>  5 Bootstrap01     0.333      0.667    14 0.00296 0.00000383 bad   Preprocessor…
#>  6 Bootstrap01     0.333      0.667    15 0.00296 0.00000383 good  Preprocessor…
#>  7 Bootstrap01     0.333      0.667    16 0.00296 0.00000383 bad   Preprocessor…
#>  8 Bootstrap01     0.334      0.666    22 0.00296 0.00000383 bad   Preprocessor…
#>  9 Bootstrap01     0.333      0.667    23 0.00296 0.00000383 good  Preprocessor…
#> 10 Bootstrap01     0.334      0.666    24 0.00296 0.00000383 bad   Preprocessor…
#> # … with 38,730 more rows
```

`augment()` 를 사용하여 예측값들이 붙어 있는 모든 리샘플의 hold-out 세트를 얻을 수 있는데, 모델 결과의 유연한 시각화를 할 수 있습니다:


```r
augment(recipe_res) %>%
  ggplot(aes(V3, .pred_good, color = Class)) +
  geom_point(show.legend = FALSE) +
  facet_wrap(~Class)
```

<img src="figs/augment-preds-1.svg" width="672" />

## 세션정보


```
#> ─ Session info  👩‍❤️‍💋‍👩  🌅  🔭   ───────────────────────────────────────
#>  hash: kiss: woman, woman, sunrise, telescope
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
#>  date     2022-03-03
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  kernlab    * 0.9-29  2019-11-12 [1] CRAN (R 4.1.0)
#>  mlbench    * 2.1-3   2021-01-29 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang      * 1.0.0   2022-01-26 [1] CRAN (R 4.1.2)
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
