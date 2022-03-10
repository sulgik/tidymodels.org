---
title: "중첩 리샘플링"
tags: [rsample, parsnip]
categories: [tuning]
type: learn-subsection
weight: 2
description: | 
  중첩 리샘플링을 사용하여 최적 하이퍼파라미터를 추정하기.
---






## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: furrr, kernlab, mlbench, scales, and tidymodels.

이 장에서는 [중첩 리샘플링(nested resampling)](https://scholar.google.com/scholar?hl=en&as_sdt=0%2C7&q=%22nested+resampling%22+inner+outer&btnG=) 이라고 부르는 모델을 평가하고 튜닝하는 다른 방법에 대해 살펴봅니다.
다른 리샘플링 방법들보다 계산이 더 걸리고 구현하기 어렵지만, 모델 성능 추정값을 더 잘 구할 수 있는 잠재력이 있습니다.

## 리샘플링 모델

예측모델을 개발할 때 데이터를 나누는 일반적인 방법은 초기데이터 분할을 훈련과 테스트셋으로 생성하는 것입니다.
rsample 에서, 모델을 적합하기 위해 사용하는 데이터를 지칭하는 용어로, _analysis set_, 성능을 계산하기 위해 사용되는 세트를 지칭하는 용어로, _assessment set_ 을 사용합니다:

<img src="figs/resampling.svg" width="70%" style="display: block; margin: auto;" />

모델을 튜닝하는 일반적인 방법은 [그리드서치](/learn/work/tune-svm/) 인데 튜닝 파라미터 후보셋이 생성됩니다.
튜닝파라미터 그리드와 리샘플의 모든 조합에 해당하는 모델의 전체 집합이 적합됩니다.
매회에는, 평가 데이터를 이용하여 성능을 측정하고, 평균값이 각 튜닝파라미터에 관해 결정됩니다.

여기에 잠재된 문제점은 가장 좋은 성능과 관계된 튜닝파라미터를 고르면, 이 성능값은 일반적으로 모델의 성능으로 인용된다는 것입니다.
같은 데이터를 사용하여 모델을 튜닝하고 성능을 평가하기 때문에 _최적화 바이어스_ 라는 심한 잠재된 위험이 있습니다.
이렇게 되면 성능이 긍정적인 추청값으로 됩니다.

중첩된 리샘플링은 모델 효과를 추정하기 위해 사용하는 프로세스로 부터 튜닝 활동을 분리하는 추가 리샘플링 레이어를 사용합니다.
_outer_ 리샘플링 방법이 사용되고, 아우터 리샘플의 모둔 분할에 대해 다른 리샘플링 분할 전체세트가 원 분섯셋에 대해 생성됩니다.
예를 들어, 10-폴드 cross-validation 이 외부에서 사용되고 5-폴드 cross-validation 이 내부에서 사용된다면, 총 500 모델이 적합될 것입니다. 
파라미터 튜닝이 10번 수행되고 최적 파라미터가 5 개 평가셋의 평균으로 결정됩니다. 
이 프로세스는 10회 반복됩니다.

튜닝 결과가 끝나면, 해당 리샘플과 연관된 최적파라미터를 사용하여 아우터 리샘플링 분할 각각에 모델이 적합됩니다.
아우터 방법의 평가셋의 평균은 모델의 unbiased 추정값입니다.

이 방법을 설명하기 위해 회귀 데이터를 시뮬레이트할 것입니다.
mlbench 패키지에는 [original MARS publication](https://scholar.google.com/scholar?hl=en&q=%22Multivariate+adaptive+regression+splines%22&btnG=&as_sdt=1%2C7&as_sdtp=) 의 복잡한 회귀 데이터 구조를 시뮬레이터 할 수 있는 `mlbench::mlbench.friedman1()` 함수가 있습니다. 
100 개의 데이터포인트가 있는 트레이닝셋과 resampling 과정이 얼마나 잘 수행되었는지를 기록하는데 사용할 더 큰 데이터셋이 생성됩니다.


```r
library(mlbench)
sim_data <- function(n) {
  tmp <- mlbench.friedman1(n, sd = 1)
  tmp <- cbind(tmp$x, tmp$y)
  tmp <- as.data.frame(tmp)
  names(tmp)[ncol(tmp)] <- "y"
  tmp
}

set.seed(9815)
train_dat <- sim_data(100)
large_dat <- sim_data(10^5)
```

## 중복 리샘플링

우선, 리샘플링 방법의 유형이 명시되어야 합니다.
데이터셋이 크지 않으므로, 10-폴드 cross-validation 5 번 반복이 전체 성능 추정값을 생성하기 위해 _outer_ 리샘플링 방법으로 사용될 것입니다.
모델은 튜닝하기 위해, 튜닝파라미터 값 각각에 대해 정확한 추정값을 얻어야 하므로, 부트스트랩 25회 반복을 사용할 것입니다.
_튜닝파라미터당_ 데이터에 적합되는 모델개수는 `5 * 10 * 25 = 1250` 가 될 것입니다.
모델 성능이 정량화되고 나면 이 모델들은 버려질 것입니다.

리샘플링 명시(specification)가 있는 티블을 생성합니다:


```r
library(tidymodels)
results <- nested_cv(train_dat, 
                     outside = vfold_cv(repeats = 5), 
                     inside = bootstraps(times = 25))
results
#> # Nested resampling:
#> #  outer: 10-fold cross-validation repeated 5 times
#> #  inner: Bootstrap sampling
#> # A tibble: 50 × 4
#>    splits          id      id2    inner_resamples      
#>    <list>          <chr>   <chr>  <list>               
#>  1 <split [90/10]> Repeat1 Fold01 <bootstraps [25 × 2]>
#>  2 <split [90/10]> Repeat1 Fold02 <bootstraps [25 × 2]>
#>  3 <split [90/10]> Repeat1 Fold03 <bootstraps [25 × 2]>
#>  4 <split [90/10]> Repeat1 Fold04 <bootstraps [25 × 2]>
#>  5 <split [90/10]> Repeat1 Fold05 <bootstraps [25 × 2]>
#>  6 <split [90/10]> Repeat1 Fold06 <bootstraps [25 × 2]>
#>  7 <split [90/10]> Repeat1 Fold07 <bootstraps [25 × 2]>
#>  8 <split [90/10]> Repeat1 Fold08 <bootstraps [25 × 2]>
#>  9 <split [90/10]> Repeat1 Fold09 <bootstraps [25 × 2]>
#> 10 <split [90/10]> Repeat1 Fold10 <bootstraps [25 × 2]>
#> # … with 40 more rows
```

리샘플 각각의 분할정보가 `split` 객체에 포함됩니다.
첫번째 반복의 두번째 폴드에 주목해보면:


```r
results$splits[[2]]
#> <Analysis/Assess/Total>
#> <90/10/100>
```

`<90/10/100>` 는 analysis 세트, assessment 셋, 원데이터의 관측값의 개수를 의미합니다.

`inner_resamples` 각 요소에는 부트스트래핑 분할을 가진 티블이 있습니다.


```r
results$inner_resamples[[5]]
#> # Bootstrap sampling 
#> # A tibble: 25 × 2
#>    splits          id         
#>    <list>          <chr>      
#>  1 <split [90/31]> Bootstrap01
#>  2 <split [90/33]> Bootstrap02
#>  3 <split [90/37]> Bootstrap03
#>  4 <split [90/31]> Bootstrap04
#>  5 <split [90/32]> Bootstrap05
#>  6 <split [90/32]> Bootstrap06
#>  7 <split [90/36]> Bootstrap07
#>  8 <split [90/34]> Bootstrap08
#>  9 <split [90/29]> Bootstrap09
#> 10 <split [90/31]> Bootstrap10
#> # … with 15 more rows
```

부트스트랩 샘플은 특정 90% 데이터의 샘플인 것을 알고 있는데, 이를 self-contained 라고 합니다:


```r
results$inner_resamples[[5]]$splits[[1]]
#> <Analysis/Assess/Total>
#> <90/31/90>
```

모델이 생성되고 측정되는 방법을 정의하는 것 부터 시작해야 합니다.
`kernlab::ksvm` 함수를 사용하여 radial basis 서포트벡트머신모델을 사용해 봅시다.
This model is generally considered to have _two_ tuning parameters: the SVM cost value and the kernel parameter `sigma`. 
이 모델은 일반적으로 _두개의_ 튜닝파라미터를 갖는데, SVM cost value 와 커널 파라미터, `sigma` 가 그 것입니다.
여기서 설명을 위해, cost 값만 튜닝할 것이고, 각 모델 적합동안 `sigma` 을 추정하기 위해 `kernlab::sigest` 함수를 사용할 것입니다.
`ksvm` 이 이것을 자동으로 수행합니다.

분석셋을 이용하여 모델을 적합하고 나면, 평가셋을 이용하여 RMSE 를 계산합니다.
**주의사항**: 이 모델에 대해 dot products 를 계산하기 전에 설명변수들을 센터링하고 스케일하는 것이 중요합니다.
`mlbench.friedman1` 가 설명변수 모드를 표준화된 유니폼 랜덤 변수로 시뮬레이트하기 때문에 우리는 여기서 이 연산을 하지 않습니다.

모델을 적합하고 RMSE 를 계산하는 함수는:


```r
library(kernlab)

# `object` will be an `rsplit` object from our `results` tibble
# `cost` is the tuning parameter
svm_rmse <- function(object, cost = 1) {
  y_col <- ncol(object$data)
  mod <- 
    svm_rbf(mode = "regression", cost = cost) %>% 
    set_engine("kernlab") %>% 
    fit(y ~ ., data = analysis(object))
  
  holdout_pred <- 
    predict(mod, assessment(object) %>% dplyr::select(-y)) %>% 
    bind_cols(assessment(object) %>% dplyr::select(y))
  rmse(holdout_pred, truth = y, estimate = .pred)$.estimate
}

# In some case, we want to parameterize the function over the tuning parameter:
rmse_wrapper <- function(cost, object) svm_rmse(object, cost)
```

중첩 리샘플링을 하기 위해, 모델이 튜닝파라미터 각각과 부트스트랩 분할 각각에 대해 적합되어야 합니다.
이를 위해 래퍼를 생성합니다:


```r
# `object` will be an `rsplit` object for the bootstrap samples
tune_over_cost <- function(object) {
  tibble(cost = 2 ^ seq(-2, 8, by = 1)) %>% 
    mutate(RMSE = map_dbl(cost, rmse_wrapper, object = object))
}
```

outer cross-validation 분할 집합들에 대해 호출될 것이기 때문에, 다른 래퍼가 필요합니다:


```r
# `object` is an `rsplit` object in `results$inner_resamples` 
summarize_tune_results <- function(object) {
  # Return row-bound tibble that has the 25 bootstrap results
  map_df(object$splits, tune_over_cost) %>%
    # For each value of the tuning parameter, compute the 
    # average RMSE which is the inner bootstrap estimate. 
    group_by(cost) %>%
    summarize(mean_RMSE = mean(RMSE, na.rm = TRUE),
              n = length(RMSE),
              .groups = "drop")
}
```

이러한 함수들이 정의되었기 때문에 이제 내부 리샘플링 루프 모두를 실행할 수 있습니다:


```r
tuning_results <- map(results$inner_resamples, summarize_tune_results) 
```

다른 방법으로는, 이 계산이 병렬로 실행될 수 있기 때문에, furrr 패키지를 사용할 수 있습니다.
`map()` 대신 `future_map()` 함수를 사용하면, [future package](https://cran.r-project.org/web/packages/future/vignettes/future-1-overview.html) 를 사용하여 반복을 병렬화할 수 있습니다.
`multisession` 플랜은 내부 리샘플링 루프를 프로세스하기 위해 로컬 코어를 사용합니다.
최종 결과는 이전의 순차적 계산했을 때와 같게 됩니다.


```r
library(furrr)
plan(multisession)

tuning_results <- future_map(results$inner_resamples, summarize_tune_results) 
```

`tuning_results` 객체는 50 개 아우터 리샘플들 각각에 대해 데이터프레임의 리스트 입니다.

내부 부트스트래핑 연산 각각에 대해 RMSE 와 튜닝파라미터 사이에 어떤 관계가 있는지를 보기 위해 평균 결과의 플롯을 그려 봅시다:


```r
library(scales)

pooled_inner <- tuning_results %>% bind_rows

best_cost <- function(dat) dat[which.min(dat$mean_RMSE),]

p <- 
  ggplot(pooled_inner, aes(x = cost, y = mean_RMSE)) + 
  scale_x_continuous(trans = 'log2') +
  xlab("SVM Cost") + ylab("Inner RMSE")

for (i in 1:length(tuning_results))
  p <- p  +
  geom_line(data = tuning_results[[i]], alpha = .2) +
  geom_point(data = best_cost(tuning_results[[i]]), pch = 16, alpha = 3/4)

p <- p + geom_smooth(data = pooled_inner, se = FALSE)
p
```

<img src="figs/rmse-plot-1.svg" width="672" />

각 회색선은 데이터의 다른 90% 에서 생성된 개별 부트스트랩 리샘플링 커브입니다.
파란선은 함께 풀링된 결과 모드의 LOESS 스무드입니다.

아우터 리샘플링 반복 각각에 해당하는 최적 파라미터 추정값을 결정합니다:


```r
cost_vals <- 
  tuning_results %>% 
  map_df(best_cost) %>% 
  select(cost)

results <- 
  bind_cols(results, cost_vals) %>% 
  mutate(cost = factor(cost, levels = paste(2 ^ seq(-2, 8, by = 1))))

ggplot(results, aes(x = cost)) + 
  geom_bar() + 
  xlab("SVM Cost") + 
  scale_x_discrete(drop = FALSE)
```

<img src="figs/choose-1.svg" width="672" />

리샘플 대부분은 최적 cost 값 2.0 을 찾았지만, 분포가 cost 값이 10 이나 그 이상이 되면 리샘플링 프로파일에서 flat trend 때문에 오른쪽으로 치우쳐 있습니다.

이 추정값들을 얻었기 때문에 이제 50 분할 각각에 대해 해당되는 튜닝 파라미터 값을 사용하여 outer resampling 결과를 계산할 수 있습니다:


```r
results <- 
  results %>% 
  mutate(RMSE = map2_dbl(splits, cost, svm_rmse))

summary(results$RMSE)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>    1.57    2.09    2.68    2.70    3.26    4.35
```

모델 튜닝 프로세스에서 추정한 RMSE 은 2.7 입니다. 
outer resampling 방법만 사용하였을 때 중첩하지 않은 과정에서 RMSE 추정값은 어떻게 됩니까?
튜닝 그리드의 cost 값 각각에 대해, 50 개의 SVM 모델이 적합되고, RMSE 값이 평균됩니다.
cost 값 테이블과 RMSE 추정값 평균을 사용하여 최적 cost 값을 결정합니다.
연관된 RMSE 는 biased estimate 입니다.


```r
not_nested <- 
  map(results$splits, tune_over_cost) %>%
  bind_rows

outer_summary <- not_nested %>% 
  group_by(cost) %>% 
  summarize(outer_RMSE = mean(RMSE), n = length(RMSE))

outer_summary
#> # A tibble: 11 × 3
#>      cost outer_RMSE     n
#>     <dbl>      <dbl> <int>
#>  1   0.25       3.54    50
#>  2   0.5        3.11    50
#>  3   1          2.77    50
#>  4   2          2.62    50
#>  5   4          2.65    50
#>  6   8          2.75    50
#>  7  16          2.82    50
#>  8  32          2.82    50
#>  9  64          2.83    50
#> 10 128          2.83    50
#> 11 256          2.82    50

ggplot(outer_summary, aes(x = cost, y = outer_RMSE)) + 
  geom_point() + 
  geom_line() + 
  scale_x_continuous(trans = 'log2') +
  xlab("SVM Cost") + ylab("RMSE")
```

<img src="figs/not-nested-1.svg" width="672" />

비중첩 과정의 RMSE 추정값은 2.62 입니다.
추정값 두 개가 꽤 서로 가깝습니다.

cost 값 2.0 의 SVM 모델의 참 RMSE 는 처음에 시뮬레이트된 큰 샘플로 근사될 수 있습니다.


```r
finalModel <- ksvm(y ~ ., data = train_dat, C = 2)
large_pred <- predict(finalModel, large_dat[, -ncol(large_dat)])
sqrt(mean((large_dat$y - large_pred) ^ 2, na.rm = TRUE))
#> [1] 2.71
```

중첩 과정은 근사 참값에 더 가까운 추정값을 생성했지만 비중첩 추정값은 매우 유사합니다.


## 세션정보


```
#> ─ Session info  ↔️  🇦🇸  🟧   ────────────────────────────────────────
#>  hash: left-right arrow, flag: American Samoa, orange square
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
#>  date     2022-03-09
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  furrr      * 0.2.3   2021-06-25 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  kernlab    * 0.9-29  2019-11-12 [1] CRAN (R 4.1.0)
#>  mlbench    * 2.1-3   2021-01-29 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        1.0.0   2022-01-26 [1] CRAN (R 4.1.2)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  scales     * 1.1.1   2020-05-11 [1] CRAN (R 4.1.0)
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
