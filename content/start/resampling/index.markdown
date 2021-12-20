---
title: "resampling 으로 모델 평가하기"
weight: 3
tags: [rsample, parsnip, tune, workflows, yardstick]
categories: [resampling]
description: | 
  Measure model performance by generating different versions of the training data through resampling.
---
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />







## 들어가기 {#intro}

지금까지 [모델을 만들고](/start/models/) [recipe 로 데이터 전처리](/start/recipes/) 를 하였습니다. 또한 [parsnip 모델](https://tidymodels.github.io/parsnip/) 과 [recipe](https://tidymodels.github.io/recipes/) 을 묶는 방법으로 [ 워크플로](/start/recipes/#fit-workflow) 를 살펴보았습니다. 트레인된 모델이 있다면, 이 모델이 새로운 데이터에 예측을 얼마나 잘 하는지를 측정할 방법이 필요합니다. 이 튜토리얼에서는 **resampling** 통계량에 기반하여 모델 성능을 정의하는 법을 설명합니다.

이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: modeldata, ranger, and tidymodels.


```r
library(tidymodels) # for the rsample package, along with the rest of tidymodels

# Helper packages
library(modeldata)  # for the cells data
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 세포 이미지 데이터 {#data}

[modeldata 패키지](https://cran.r-project.org/web/packages/modeldata/index.html) 에 있는 [Hill, LaPan, Li, and Haney (2007)](http://www.biomedcentral.com/1471-2105/8/340) 데이터를 사용하여, resampling 으로 세포 이미지 세그멘테이션 품질을 예측해 봅시다. 이 데이터를 R 에 로드합니다:


```r
data(cells, package = "modeldata")
cells
#> # A tibble: 2,019 × 58
#>   case  class angle_ch_1 area_ch_1 avg_inten_ch_1 avg_inten_ch_2 avg_inten_ch_3
#>   <fct> <fct>      <dbl>     <int>          <dbl>          <dbl>          <dbl>
#> 1 Test  PS        143.         185           15.7           4.95           9.55
#> 2 Train PS        134.         819           31.9         207.            69.9 
#> 3 Train WS        107.         431           28.0         116.            63.9 
#> 4 Train PS         69.2        298           19.5         102.            28.2 
#> 5 Test  PS          2.89       285           24.3         112.            20.5 
#> # … with 2,014 more rows, and 51 more variables: avg_inten_ch_4 <dbl>,
#> #   convex_hull_area_ratio_ch_1 <dbl>, convex_hull_perim_ratio_ch_1 <dbl>,
#> #   diff_inten_density_ch_1 <dbl>, diff_inten_density_ch_3 <dbl>, …
```

2019 개의 세포와 58 개의 변수가 있는 데이터가 있습니다. 여기에서 우리가 관심있는 주 반응변수는 `class` 인데, 팩터형임을 알 수 있습니다. 하지만 `class` 변수 예측을 시작하기에 앞서 이 변수에 대해 더 이해할 필요가 있습니다. 아래는 세포 이미지 세그멘테이션에 대한 간략한 서문입니다.

### 이미지 세그멘테이션 품질 예측하기

세포 실험을 하는 생물학자들이 있습니다. 제약분야에서 특정유형의 세포가 약이나 대조군 으로 취급한 후 (나타나게 될) 효과를 관측합니다. 이러한 종류의 측정에 있어 보통의 방법은 세포 이미징입니다. 세포의 다른 부분들이 색칠이 칠해져서 세포의 위치가 결정될 수 있습니다.

예를들어, 세포 다섯개가 있는 이미지의 위 패널에서 녹색은 세포 경계를 의미하지만 (cytoskeleton 이라고 하는 염색) 청색은 세포 핵을 보여줍니다.

<img src="img/cells.png" width="70%" style="display: block; margin: auto;" />

이러한 색깔을 이용해서 이미지 안의 세포는 _경계를 잡아 (segmented)_ 서 어떤 픽셀이 어떤 세포에 속하는지 알아낼 수 있습니다. 이 과정이 잘 된다면, 세포가 다양한 방법으로 측정이 되어 생물학 연구에 있어 중요할 수 있습니다. 세포 모양이 중요한 경우가 있어 크기나 "장방형" 같은 특징들을 요약하는데 다양한 수학적 도구가 사용됩니다. 

아래 패널은 세그멘테이션 결과를 보여줍니다. 1번과 5번 세포는 꽤 잘 세그멘트되었습니다. 하지만, 3번 4번 세포는 세그멘테이션이 잘 되지 않았기 때문에 뭉쳐져 있습니다. 세그멘테이션이 잘 되지 않으면, 데이터 오염이 됩니다; 생물학자는 이러한 세포의 모양이나 크기를 분석할 때, 데이터가 정확하지 않고 잘못된 결론을 도출하게 됩니다.  

세포 기반 실험은 수백만 세포를 다루므로 이들을 모두 시각적으로 살펴보는 것은 불가능합니다. 대신, 서브샘플을 생성하여 전문가가 잘못 세그멘트됨 (`PS`), 잘 세그멘트됨 (`WS`) 중 하나로 수동으로 라벨할 수 있습니다. 이러한 라벨을 정확하게 예측할 수 있으면, 잘못 세그멘트된 것 같은 세포들을 필터링하여 대량의 데이터가 개선될 수 있습니다. 

### 세포 데이터 돌아가기

`cells` 데이터에는 2019 세포의 `class` 라벨이 있습니다 &mdash; 각 세포는 잘못 세그멘트됨 (`PS`), 잘 세그멘트됨 (`WS`) 중 하나로 라벨링 됩니다. 각 세포는 자동 이미지 분석 측정값들에 기반하여 총 56 개의 설명변수가 있습니다. 예를 들어, `avg_inten_ch_1` 는 핵에 포함된 데이터의 평균강도이고, `area_ch_1` 은 세포의 총 크기, 등입니다. (몇몇 설명변수는 의미가 파악이 안됨)


```r
cells
#> # A tibble: 2,019 × 58
#>   case  class angle_ch_1 area_ch_1 avg_inten_ch_1 avg_inten_ch_2 avg_inten_ch_3
#>   <fct> <fct>      <dbl>     <int>          <dbl>          <dbl>          <dbl>
#> 1 Test  PS        143.         185           15.7           4.95           9.55
#> 2 Train PS        134.         819           31.9         207.            69.9 
#> 3 Train WS        107.         431           28.0         116.            63.9 
#> 4 Train PS         69.2        298           19.5         102.            28.2 
#> 5 Test  PS          2.89       285           24.3         112.            20.5 
#> # … with 2,014 more rows, and 51 more variables: avg_inten_ch_4 <dbl>,
#> #   convex_hull_area_ratio_ch_1 <dbl>, convex_hull_perim_ratio_ch_1 <dbl>,
#> #   diff_inten_density_ch_1 <dbl>, diff_inten_density_ch_3 <dbl>, …
```

클래스들의 비율은 다소 불균형입니다; 잘 세그멘트된 세포들보다 잘못 세그멘트된 세포들이 더 많습니다. 


```r
cells %>% 
  count(class) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   class     n  prop
#>   <fct> <int> <dbl>
#> 1 PS     1300 0.644
#> 2 WS      719 0.356
```

## 데이터 나누기 {#data-split}

이전의 [*recipe 로 데이터 전처리하기*](/start/recipes/#data-split) 장에서 데이터 나누기 부터 시작했었습니다. 모델링 프로젝트를 시작할 때, 보통 [데이터셋을 두 부분으로 분리](https://bookdown.org/max/FES/data-splitting.html)부터 합니다: 

 * _트레이닝셋_ 은 파라미터를 추정하고, 모델과 피쳐엔지니어링 기술을 비교하고, 모델을 튜닝하는 등에 이용됩니다.

 * _테스트셋_ 은 프로젝트 마지막에 사용되는데, 이 시점에서는 심각하게 고려하는 모델이 한개나 두개 정도여야 합니다. 최종 모델 성능측정을 위한 unbiased source 로 사용됩니다.

데이터를 이렇게 나누는 법은 여러 방법이 있습니다. 가장 일반적인 방법은 랜덤샘플을 이용하는 것입니다. 데이터 사분의 일이 테스트셋으로 분리되었다고 가정합니다. 랜덤샘플링은 25% 를 랜덤하게 선택하여 테스트셋을 만들고, 나머지를 트레이닝셋으로 사용합니다. [rsample](https://tidymodels.github.io/rsample/) 패키지를 사용하여 이렇게 할 수 있습니다. 

랜덤 샘플링은 랜덤넘버를 사용하기 때문에, 랜덤넘버 씨드를 설정하는 것이 중요합니다. 랜덤넘버는 (필요시) 나중에 랜덤넘버를 재현할 수 있게 해 줍니다. 

함수 `rsample::initial_split()` 은 원데이터를 입력으로, 어떻게 분리하는 지에 대한 정보를 저장합니다. 원 분석에서, 저자들은 자신들만의 트레이닝/테스트셋을 만들었고, 이 정보는 `case`열에 저장됩니다. 나눈 방법을 보여주기 위해, 우리만의 분리를 하기 전에 이 열을 제거할 것입니다:


```r
set.seed(123)
cell_split <- initial_split(cells %>% select(-case), 
                            strata = class)
```

여기서 우리는 [`strata` 인수](https://tidymodels.github.io/rsample/reference/initial_split.html) 를 사용했는데, 이는 층화분리를 수행합니다. 우리 `class` 변수에서 발견한 불균형에도 불구하고 우리 트레이닝과 테스트셋은 잘못 세그멘트, 잘 세그멘트된 세포의 비율을 원데이터와 대략 같게 유지하게 해 줍니다. `initial_split` 을 한 후 `training()` 과 `testing()` 함수들은 실제 데이터셋을 반환합니다.


```r
cell_train <- training(cell_split)
cell_test  <- testing(cell_split)

nrow(cell_train)
#> [1] 1514
nrow(cell_train)/nrow(cells)
#> [1] 0.7498762

# training set proportions by class
cell_train %>% 
  count(class) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   class     n  prop
#>   <fct> <int> <dbl>
#> 1 PS      975 0.644
#> 2 WS      539 0.356

# test set proportions by class
cell_test %>% 
  count(class) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   class     n  prop
#>   <fct> <int> <dbl>
#> 1 PS      325 0.644
#> 2 WS      180 0.356
```

이후 트레이닝데이터셋을 이용하여 모델링 작업의 대부분을 수행합니다.


## 모델링

[랜덤포레스트 모델](https://en.wikipedia.org/wiki/Random_forest) 은 [decision tree](https://en.wikipedia.org/wiki/Decision_tree) 의  [앙상블](https://en.wikipedia.org/wiki/Ensemble_learning) 입니다. 약간 다른 트레이닝 셋에 기반하여 많은 수의 decision tree 모델이 생성됩니다. 각 decision tree 가 생성될 때, 적합과정은 최대한 decision tree 들이 다양하게 되길 유도합니다. 트리의 집합은 랜덤포레스트 모델로 조합되고, 새로운 샘플이 예측될 때, 각 트리로 부터의 투표가 최종 예측값을 계산하는데 사용됩니다. 우리의 `cells` 예시 데이터의 `class` 와 같은 범주형 종속변수에 대해, 랜덤포레스트의 모든 트리를 통틀어 가장 많은 투표를 받은 모델이 새로운 샘플의 예측 범주를 결정합니다. 

랜덤 포레스트 모델의 장점 중 하나는 유지에 손이 거의 들지 않는다는 것입니다. 데이터 전처리를 할 필요가 거의 없고, 기본값 파라미터들이 괜찮은 결과를 제공합니다. 이러한 이유로 우리는 `cells` 데이터를 위해 레시피를 생성하지는 않을 것입니다. 

동시에, 렌덤포레스트라는 이 앙상블 모델의 나무 개수는 커야하고 (수천), 이로 인해 모델을 계산하는데 꽤 시간이 걸립니다.

[parsnip](https://tidymodels.github.io/parsnip/) 패키지를 [ranger](https://cran.r-project.org/web/packages/ranger/index.html) 엔진과 함께 사용하여 랜덤 포레스트 모델을 적합해 봅시다. 우리가 생성하고 싶은 모델을 우선 정의합니다:


```r
rf_mod <- 
  rand_forest(trees = 1000) %>% 
  set_engine("ranger") %>% 
  set_mode("classification")
```

위의 parsnip 모델 객체부터 시작하여 `fit()` 함수는 모델 공식과 함께 사용될 수 있습니다. 랜덤포레스트 모델은 랜덤 넘버를 사용하기 때문에, 계산에 앞서 시드를 한번더 설정합니다: 


```r
set.seed(234)
rf_fit <- 
  rf_mod %>% 
  fit(class ~ ., data = cell_train)
rf_fit
#> parsnip model object
#> 
#> Fit time:  2.3s 
#> Ranger result
#> 
#> Call:
#>  ranger::ranger(x = maybe_data_frame(x), y = y, num.trees = ~1000,      num.threads = 1, verbose = FALSE, seed = sample.int(10^5,          1), probability = TRUE) 
#> 
#> Type:                             Probability estimation 
#> Number of trees:                  1000 
#> Sample size:                      1514 
#> Number of independent variables:  56 
#> Mtry:                             7 
#> Target node size:                 10 
#> Variable importance mode:         none 
#> Splitrule:                        gini 
#> OOB prediction error (Brier s.):  0.1189338
```

새롭게 만들어진 `rf_fit` 객체는 트레이닝 데이터셋에서 트레이닝된 적합된 모델입니다. 


## 성능 추정하기 {#performance}

모델링 프로젝트 동안, 우리는 다양한 모델을 생성할 수 있습니다. 이들 중 선택하기 위해 이러한 모델들이 얼마나 잘 되는지, 성능 통계량들을 측정하여 고려해야 합니다. 이 장의 예에서, 사용할 수 있는 선택지들은 다음과 같습니다:

 * the area under the Receiver Operating Characteristic (ROC) curve
 
 * 종합 분류 정확도 (accuracy).
 
ROC 커브는 클래스 확률 추정값을 사용하여 잠재 확률 컷오프의 전체셋을 통해 성능 감도를 제공합니다. Hard class 예측값은 각 세포마다 `PS`, `WS` 를 예측했는지를 알려줍니다. 하지만, 이러한 예측 뒤에, 모델은 확률을 사실을 측정합니다. 50% 확률 컷오프가 자ㅏㄹ못 세그멘트된 것으로 분류하기 위해 사용됩니다. 

[yardstick 패키지](https://tidymodels.github.io/yardstick/) 에는 이러한 두 측정값들을 계산하는 함수, `roc_auc()` 와 `accuracy()` 가 있습니다. 

처음 보아서는 이러한 통계량을 계산하기 위해 트레이닝 셋 데이터를 사용하는 것이 좋아 보입니다. (이는 사실 매우 나쁜 생각입니다.) 이렇게 했을때 어떤 일이 일어나는지 살펴봅시다. 트레이닝셋에 기반하여 성능을 측정하기 위해 `predict()` 메소드를 호출하여 두 종류의 예측 (즉, 확률과 hard class 예측) 을 구합니다. 


```r
rf_training_pred <- 
  predict(rf_fit, cell_train) %>% 
  bind_cols(predict(rf_fit, cell_train, type = "prob")) %>% 
  # Add the true outcome data back in
  bind_cols(cell_train %>% 
              select(class))
```

yardstick 함수들을 사용하여, 이 모델은 엄청난 결과를 보여주는데, 결과가 너무 엄청나서 의심이 생기기 시작할 것입니다: 


```r
rf_training_pred %>%                # training set predictions
  roc_auc(truth = class, .pred_PS)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary          1.00
rf_training_pred %>%                # training set predictions
  accuracy(truth = class, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy binary         0.991
```

이 모델이 매우 성능이 좋기 때문에, 테스트셋으로 진행합니다. 우리 결과가 나쁘지는 않지만, 트레이닝셋 예측작업에 기반하여 처음 기대했던 것 보다 훨씬 좋지 않습니다.


```r
rf_testing_pred <- 
  predict(rf_fit, cell_test) %>% 
  bind_cols(predict(rf_fit, cell_test, type = "prob")) %>% 
  bind_cols(cell_test %>% select(class))
```


```r
rf_testing_pred %>%                   # test set predictions
  roc_auc(truth = class, .pred_PS)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.891
rf_testing_pred %>%                   # test set predictions
  accuracy(truth = class, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy binary         0.816
```

### 무슨일이 일어난 거야?

이 섹션에서 보이는 것 같이 트레이닝셋 통계량이 실제와 다르게 긍정적인 것에서는 여러 이유가 있습니다. 

* 랜덤포레스트, 뉴럴 네트워크, 다른 블랙박스 방법들 같은 모델들은 트레이닝셋을 본질적으로 암기할 수 있습니다. 같은 셋을 다시 예측하면 항상 거의 완벽한 결과를 제공할 수 밖에 없다. 
강의 
* The training set does not have the capacity to be a good arbiter of performance. It is not an independent piece of information; predicting the training set can only reflect what the model already knows. 

To understand that second point better, think about an analogy from teaching. Suppose you give a class a test, then give them the answers, then provide the same test. The student scores on the _second_ test do not accurately reflect what they know about the subject; these scores would probably be higher than their results on the first test. 



## Resampling 를 이용한 문제해결 {#resampling}

cross-validation 과 bootstrap 과 같은 resampling 방법은 실험적 시뮬레이션 시스템입니다. 이들은 이전에 논의한 training/testing 분할과 유사하게 데이터셋 일련을 생성합니다. 이 데이터셋의 서브셋은 모델을 생성하는데 사용되고 다른 서브셋은 성능을 측정하는데 사용됩니다. 리샘플링은 항상 _트레이닝셋_ 과 사용됩니다. [Kuhn and Johnson (2019)](https://bookdown.org/max/FES/resampling.html) 의 스케매틱에서 리샘플링 메소드의 데이터 사용을 보여줍니다:

<img src="img/resampling.svg" width="85%" style="display: block; margin: auto;" />

이 다이어그램의 첫번째 수준에서, `rsample::initial_split()` 을 사용할 때 일어나는 일을 볼 수 있는데, 원 데이터를 트레이닝과 테스트셋으로 분할합니다. 그 후 트레이닝셋이 리샘플링을 위해 선택되고 테스트셋은 보존됩니다.

이 예에서 10-폴드 cross-validation (CV) 를 오
Let's use 10-fold cross-validation (CV) in this example. This method randomly allocates the 1514 cells in the training set to 10 groups of roughly equal size, called "folds". For the first iteration of resampling, the first fold of about 151 cells are held out for the purpose of measuring performance. This is similar to a test set but, to avoid confusion, we call these data the _assessment set_ in the tidymodels framework. 

The other 90% of the data (about 1362 cells) are used to fit the model. Again, this sounds similar to a training set, so in tidymodels we call this data the _analysis set_. This model, trained on the analysis set, is applied to the assessment set to generate predictions, and performance statistics are computed based on those predictions. 

In this example, 10-fold CV moves iteratively through the folds and leaves a different 10% out each time for model assessment. At the end of this process, there are 10 sets of performance statistics that were created on 10 data sets that were not used in the modeling process. For the cell example, this means 10 accuracies and 10 areas under the ROC curve. While 10 models were created, these are not used further; we do not keep the models themselves trained on these folds because their only purpose is calculating performance metrics. 



The final resampling estimates for the model are the **averages** of the performance statistics replicates. For example, suppose for our data the results were: 

<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
  <tr>
   <th style="text-align:left;"> resample </th>
   <th style="text-align:right;"> accuracy </th>
   <th style="text-align:right;"> roc_auc </th>
   <th style="text-align:right;"> assessment size </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> Fold01 </td>
   <td style="text-align:right;"> 0.8289474 </td>
   <td style="text-align:right;"> 0.8937128 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold02 </td>
   <td style="text-align:right;"> 0.7697368 </td>
   <td style="text-align:right;"> 0.8768989 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold03 </td>
   <td style="text-align:right;"> 0.8552632 </td>
   <td style="text-align:right;"> 0.9017666 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold04 </td>
   <td style="text-align:right;"> 0.8552632 </td>
   <td style="text-align:right;"> 0.8928076 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold05 </td>
   <td style="text-align:right;"> 0.7947020 </td>
   <td style="text-align:right;"> 0.8816342 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold06 </td>
   <td style="text-align:right;"> 0.8476821 </td>
   <td style="text-align:right;"> 0.9244306 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold07 </td>
   <td style="text-align:right;"> 0.8145695 </td>
   <td style="text-align:right;"> 0.8960339 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold08 </td>
   <td style="text-align:right;"> 0.8543046 </td>
   <td style="text-align:right;"> 0.9267677 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold09 </td>
   <td style="text-align:right;"> 0.8543046 </td>
   <td style="text-align:right;"> 0.9231392 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold10 </td>
   <td style="text-align:right;"> 0.8476821 </td>
   <td style="text-align:right;"> 0.9266917 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
</tbody>
</table>

From these resampling statistics, the final estimate of performance for this random forest model would be 0.904 for the area under the ROC curve and 0.832 for accuracy. 

These resampling statistics are an effective method for measuring model performance _without_ predicting the training set directly as a whole. 

## Fit a model with resampling {#fit-resamples}

To generate these results, the first step is to create a resampling object using rsample. There are [several resampling methods](https://tidymodels.github.io/rsample/reference/index.html#section-resampling-methods) implemented in rsample; cross-validation folds can be created using `vfold_cv()`: 


```r
set.seed(345)
folds <- vfold_cv(cell_train, v = 10)
folds
#> #  10-fold cross-validation 
#> # A tibble: 10 × 2
#>    splits             id    
#>    <list>             <chr> 
#>  1 <split [1362/152]> Fold01
#>  2 <split [1362/152]> Fold02
#>  3 <split [1362/152]> Fold03
#>  4 <split [1362/152]> Fold04
#>  5 <split [1363/151]> Fold05
#>  6 <split [1363/151]> Fold06
#>  7 <split [1363/151]> Fold07
#>  8 <split [1363/151]> Fold08
#>  9 <split [1363/151]> Fold09
#> 10 <split [1363/151]> Fold10
```

The list column for `splits` contains the information on which rows belong in the analysis and assessment sets. There are functions that can be used to extract the individual resampled data called `analysis()` and `assessment()`. 

However, the tune package contains high-level functions that can do the required computations to resample a model for the purpose of measuring performance. You have several options for building an object for resampling:

+ Resample a model specification preprocessed with a formula or [recipe](/start/recipes/), or 

+ Resample a [`workflow()`](https://tidymodels.github.io/workflows/) that bundles together a model specification and formula/recipe. 

For this example, let's use a `workflow()` that bundles together the random forest model and a formula, since we are not using a recipe. Whichever of these options you use, the syntax to `fit_resamples()` is very similar to `fit()`: 


```r
rf_wf <- 
  workflow() %>%
  add_model(rf_mod) %>%
  add_formula(class ~ .)

set.seed(456)
rf_fit_rs <- 
  rf_wf %>% 
  fit_resamples(folds)
```


```r
rf_fit_rs
#> # Resampling results
#> # 10-fold cross-validation 
#> # A tibble: 10 × 4
#>    splits             id     .metrics         .notes          
#>    <list>             <chr>  <list>           <list>          
#>  1 <split [1362/152]> Fold01 <tibble [2 × 4]> <tibble [0 × 1]>
#>  2 <split [1362/152]> Fold02 <tibble [2 × 4]> <tibble [0 × 1]>
#>  3 <split [1362/152]> Fold03 <tibble [2 × 4]> <tibble [0 × 1]>
#>  4 <split [1362/152]> Fold04 <tibble [2 × 4]> <tibble [0 × 1]>
#>  5 <split [1363/151]> Fold05 <tibble [2 × 4]> <tibble [0 × 1]>
#>  6 <split [1363/151]> Fold06 <tibble [2 × 4]> <tibble [0 × 1]>
#>  7 <split [1363/151]> Fold07 <tibble [2 × 4]> <tibble [0 × 1]>
#>  8 <split [1363/151]> Fold08 <tibble [2 × 4]> <tibble [0 × 1]>
#>  9 <split [1363/151]> Fold09 <tibble [2 × 4]> <tibble [0 × 1]>
#> 10 <split [1363/151]> Fold10 <tibble [2 × 4]> <tibble [0 × 1]>
```

The results are similar to the `folds` results with some extra columns. The column `.metrics` contains the performance statistics created from the 10 assessment sets. These can be manually unnested but the tune package contains a number of simple functions that can extract these data: 
 

```r
collect_metrics(rf_fit_rs)
#> # A tibble: 2 × 6
#>   .metric  .estimator  mean     n std_err .config             
#>   <chr>    <chr>      <dbl> <int>   <dbl> <chr>               
#> 1 accuracy binary     0.832    10 0.00952 Preprocessor1_Model1
#> 2 roc_auc  binary     0.904    10 0.00610 Preprocessor1_Model1
```

Think about these values we now have for accuracy and AUC. These performance metrics are now more realistic (i.e. lower) than our ill-advised first attempt at computing performance metrics in the section above. If we wanted to try different model types for this data set, we could more confidently compare performance metrics computed using resampling to choose between models. Also, remember that at the end of our project, we return to our test set to estimate final model performance. We have looked at this once already before we started using resampling, but let's remind ourselves of the results:


```r
rf_testing_pred %>%                   # test set predictions
  roc_auc(truth = class, .pred_PS)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.891
rf_testing_pred %>%                   # test set predictions
  accuracy(truth = class, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy binary         0.816
```

The performance metrics from the test set are much closer to the performance metrics computed using resampling than our first ("bad idea") attempt. Resampling allows us to simulate how well our model will perform on new data, and the test set acts as the final, unbiased check for our model's performance.



## Session information


```
#> ─ Session info  🌒  💑  🇳🇱   ───────────────────────────────────────
#>  hash: waxing crescent moon, couple with heart, flag: Netherlands
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
#>  date     2021-12-20
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.10  2021-10-31 [1] CRAN (R 4.1.0)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  modeldata  * 0.1.1   2021-07-14 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  ranger     * 0.13.1  2021-07-14 [1] CRAN (R 4.1.0)
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
