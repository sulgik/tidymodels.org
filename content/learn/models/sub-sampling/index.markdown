---
title: "Class 불균형 상황에서 서브샘플링"
tags: [recipes, themis, discrim, parsnip]
categories: [model fitting, pre-processing]
type: learn-subsection
weight: 3
description: | 
  Improve model performance in imbalanced data sets through undersampling or oversampling.
---






## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: discrim, klaR, readr, ROSE, themis, and tidymodels.

적절한 클래스를 언더샘플링하거나 오버샘플링 하는, 훈련데이테섯 서브샘플링은 하나 이상의 클래스가 잘 나오지 않는 classification 데이터를 다루는데 도움이 될 수 있습니다. 이러한 상황에서 (보충하지 않으면) 대부분의 모델은 다수 클래스에 과적합될 수 있고, 다수 클래스에 대해서는 매우 좋은 통계량을 산출하지만, 소수 클래스들에 대해서는 낮은 성적을 보여줍니다.

이 문서는 클래스 임밸런스를 다루는 서브샘플링을 설명합니다. 더 잘 이해하기 위해, 민감도(sensitivity), 특이도(specificity), roc 커브와 같은 classification 지표들에 대해 지식이 조금 필요합니다. [Kuhn and Johnson (2019)](https://bookdown.org/max/FES/measuring-performance.html) 의 섹션 3.2.2 에서 이러한 지표들에 대해 자세히 알아보세요.

## 시뮬레이션 데이터

첫번째 클래스가 거의 일어나지 않는 두 클래스 문제를 고려해봅시다. 데이터는 시뮬레이션 되었고, 아래 코드를 이용해서 R 로 불러올 수 있습니다.


```r
imbal_data <- 
  readr::read_csv("https://bit.ly/imbal_data") %>% 
  mutate(Class = factor(Class))
dim(imbal_data)
#> [1] 1200   16
table(imbal_data$Class)
#> 
#> Class1 Class2 
#>     60   1140
```

"Class1" 가 관심있는 이벤트라면, 어떤 classification 모델은 매우 좋은 _특이도_ 를 갖게 되기 쉬울 것이데, 데이터 대부분이 두번째 클래스이기 때문이다. 

그러나, _민감도_ 가 낮을 가능서이 큰데, 모델이 모든 것을 다수 클래스로 예측해서 정확도(혹은 로스 함수)를 최적화할 것이기 때문이다.

클래스 불균형의 결과 중 하나는 기본값 확률 컷오프를 50%로 하는 것이 부적절하다는 것입니다. 더 극단적인 컷오프값이 성능이 더 좋을 수 있습니다. 

## 데이터 서브샘플링하기

이 이슈를 누그러뜨리는 방법 중 하나는 데이터를 _서브샘플링_ 하는 것입니다. 이를 수행하는 방법은 많지만, 가장 간단한 방법은 다수 클래스와 소수 클래스가 같은 빈도가 될 때 까지 _다운샘플링_ (undersample) 하는 것입니다. 직관과 반하는 것 같지만, 데이터 많은 부분을 버리는 것은 다수와 소수 클래스를 모두 인식하는 유용한 모델을 만드는 것에 효과적일 수 있습니다. 어떤 경우, 모델의 전체 성능이 더 나아지는 것을 의미합니다. (예 ROC 커브 아래 면적이 개선됨) 하지만, 서브샘플링은 더 잘 캘리브레이트되는 모델을 항상 산출하는데 이는 클래스 확률의 분포가 더 잘 작동한다는 것을 의미합니다. 결과로 기본값 50% 컷오프 값은 민감도와 특이도가 더 나아집니다. 

우리 시뮬레이션 데이터를 위한 레시피에 있는 `themis::step_rose()` 를 사용한 서브샘플링을 탐색해봅시다. [Menardi, G. and Torelli, N. (2014)](https://scholar.google.com/scholar?hl=en&q=%22training+and+assessing+classification+rules+with+imbalanced+data%22) 의 ROSE (random over sampling examples) 방법을 사용합니다. 언더샘플링이 아닌 오버샘플링의 예입니다.


워크플로우는:

 * 서브샘플링은 _리샘플링 내_에서 일어난다는 것이 매유 중요합니다. 그렇지 않으면, 리샘플링프로세스는 [모델성능이 안좋을](https://topepo.github.io/caret/subsampling-for-class-imbalances.html#resampling) 수 있습니다. 
 * 서브샘플링은 분석셋에 적용되어야만 합니다. 측정 셋은 이벤트 빈도가 "야생"에서 측정도니 이벤트 빈도를 반영해야하고, 이러한 이유로  argument to `step_downsample()` 와 다른 서브샘플링 단계의 `skip` 인수는 기본값 `TRUE` 를 같습니다. 

다음은 오버샘플링을 구현하는 간단한 레시피이다:


```r
library(tidymodels)
library(themis)
imbal_rec <- 
  recipe(Class ~ ., data = imbal_data) %>%
  step_rose(Class)
```

[quadratic discriminant analysis](https://en.wikipedia.org/wiki/Quadratic_classifier#Quadratic_discriminant_analysis) (QDA) 모델을 우리의 모델로 선택해 봅니다. discrim 패키지에서 다음을 이용해서 QDA 모델을 정의할 수 있습니다:


```r
library(discrim)
qda_mod <- 
  discrim_regularized(frac_common_cov = 0, frac_identity = 0) %>% 
  set_engine("klaR")
```

[workflow](https://tidymodels.github.io/workflows/) 에서 객체들을 묶을 수 있습니다:


```r
qda_rose_wflw <- 
  workflow() %>% 
  add_model(qda_mod) %>% 
  add_recipe(imbal_rec)
qda_rose_wflw
#> ══ Workflow ══════════════════════════════════════════════════════════
#> Preprocessor: Recipe
#> Model: discrim_regularized()
#> 
#> ── Preprocessor ──────────────────────────────────────────────────────
#> 1 Recipe Step
#> 
#> • step_rose()
#> 
#> ── Model ─────────────────────────────────────────────────────────────
#> Regularized Discriminant Model Specification (classification)
#> 
#> Main Arguments:
#>   frac_common_cov = 0
#>   frac_identity = 0
#> 
#> Computational engine: klaR
```

## 모델 성능

모델을 리샘플하는데 층화 10-fold cross-validation 을 사용합니다:


```r
set.seed(5732)
cv_folds <- vfold_cv(imbal_data, strata = "Class", repeats = 5)
```

모델 성능을 측정하기 위해 두개의 지표를 사용합시다:

 * Area under [ROC curve](https://en.wikipedia.org/wiki/Receiver_operating_characteristic) 는 _모든_ 컷오프값을 통튼 전체 성능을 측정값입니다. 1 에 가까운 값은 매우 좋은 가까운 값은 매우 좋은 결과를 의미하고, 0.5 근처의 값은 모델 성능이 매우 좋지 않음을 의미합니다.  
 * The _J_ 인덱스 (a.k.a. [Youden's _J_](https://en.wikipedia.org/wiki/Youden%27s_J_statistic) statistic) is `sensitivity + specificity - 1`. Values near one are once again best. 

If a model is poorly calibrated, the ROC curve value might not show diminished performance. However, the _J_ index would be lower for models with pathological distributions for the class probabilities. The yardstick package will be used to compute these metrics. 


```r
cls_metrics <- metric_set(roc_auc, j_index)
```

Now, we train the models and generate the results using `tune::fit_resamples()`:


```r
set.seed(2180)
qda_rose_res <- fit_resamples(
  qda_rose_wflw, 
  resamples = cv_folds, 
  metrics = cls_metrics
)

collect_metrics(qda_rose_res)
#> # A tibble: 2 × 6
#>   .metric .estimator  mean     n std_err .config             
#>   <chr>   <chr>      <dbl> <int>   <dbl> <chr>               
#> 1 j_index binary     0.773    50 0.0231  Preprocessor1_Model1
#> 2 roc_auc binary     0.948    50 0.00544 Preprocessor1_Model1
```

What do the results look like without using ROSE? We can create another workflow and fit the QDA model along the same resamples:


```r
qda_wflw <- 
  workflow() %>% 
  add_model(qda_mod) %>% 
  add_formula(Class ~ .)

set.seed(2180)
qda_only_res <- fit_resamples(qda_wflw, resamples = cv_folds, metrics = cls_metrics)
collect_metrics(qda_only_res)
#> # A tibble: 2 × 6
#>   .metric .estimator  mean     n std_err .config             
#>   <chr>   <chr>      <dbl> <int>   <dbl> <chr>               
#> 1 j_index binary     0.250    50 0.0288  Preprocessor1_Model1
#> 2 roc_auc binary     0.953    50 0.00479 Preprocessor1_Model1
```

It looks like ROSE helped a lot, especially with the J-index. Class imbalance sampling methods tend to greatly improve metrics based on the hard class predictions (i.e., the categorical predictions) because the default cutoff tends to be a better balance of sensitivity and specificity. 

Let's plot the metrics for each resample to see how the individual results changed. 


```r
no_sampling <- 
  qda_only_res %>% 
  collect_metrics(summarize = FALSE) %>% 
  dplyr::select(-.estimator) %>% 
  mutate(sampling = "no_sampling")

with_sampling <- 
  qda_rose_res %>% 
  collect_metrics(summarize = FALSE) %>% 
  dplyr::select(-.estimator) %>% 
  mutate(sampling = "rose")

bind_rows(no_sampling, with_sampling) %>% 
  mutate(label = paste(id2, id)) %>%  
  ggplot(aes(x = sampling, y = .estimate, group = label)) + 
  geom_line(alpha = .4) + 
  facet_wrap(~ .metric, scales = "free_y")
```

<img src="figs/merge-metrics-1.svg" width="672" />

This visually demonstrates that the subsampling mostly affects metrics that use the hard class predictions. 

## Session information


```
#> ─ Session info  👩🏾‍✈️  🎢  🥚   ───────────────────────────────────────
#>  hash: woman pilot: medium-dark skin tone, roller coaster, egg
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
#>  date     2021-12-16
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.10  2021-10-31 [1] CRAN (R 4.1.0)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  discrim    * 0.1.3   2021-07-21 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  klaR       * 0.6-15  2020-02-19 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  readr      * 2.1.0   2021-11-11 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
#>  ROSE       * 0.0-4   2021-06-14 [1] CRAN (R 4.1.0)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  themis     * 0.1.4   2021-06-12 [1] CRAN (R 4.1.0)
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

