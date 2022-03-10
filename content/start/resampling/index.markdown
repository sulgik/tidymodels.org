---
title: "리샘플링으로 모델 평가하기"
weight: 3
tags: [rsample, parsnip, tune, workflows, yardstick]
categories: [resampling]
description: | 
  Measure model performance by generating different versions of the training data through resampling.
---
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />







## 들어가기 {#intro}

지금까지 [모델을 만들고](/start/models/) [레시피로 데이터 전처리](/start/recipes/)를 하였습니다. 
또한 [parsnip 모델](https://tidymodels.github.io/parsnip/)과 [레시피](https://tidymodels.github.io/recipes/)를 묶는 방법으로 [워크플로](/start/recipes/#fit-workflow)를 살펴보았습니다. 
훈련된 모델이 있다면, 이 모델이 새로운 데이터에 예측을 얼마나 잘 하는지를 측정할 방법이 필요합니다.
이 튜토리얼에서는 **리샘플링** 통계량에 기반하여 모델 성능을 정의하는 법을 설명합니다.

이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: modeldata, ranger, and tidymodels.


```r
library(tidymodels) # for the rsample package, along with the rest of tidymodels

# Helper packages
library(modeldata)  # for the cells data
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 세포 이미지 데이터 {#data}

[modeldata 패키지](https://cran.r-project.org/web/packages/modeldata/index.html) 에 있는 [Hill, LaPan, Li, and Haney (2007)](http://www.biomedcentral.com/1471-2105/8/340) 데이터를 사용하여, 리샘플링으로 세포 이미지 세그멘테이션 품질을 예측해 봅시다. 
이 데이터를 R 에 로드합니다:


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

2019 개의 세포와 58 개의 변수가 있는 데이터가 있습니다. 
여기에서 우리가 관심있는 주 반응변수는 `class` 인데, 팩터형입니다. 
하지만 `class` 변수 예측을 시작하기에 앞서 이 변수에 대해 더 이해할 필요가 있습니다. 
아래는 세포 이미지 세그멘테이션에 대한 간략한 서문입니다.

### 이미지 세그멘테이션 품질 예측하기

세포 실험을 하는 생물학자들이 있습니다. 제약분야에서 특정유형의 세포가 약이나 대조군 으로 취급한 후 (나타나게 될) 효과를 관측합니다. 이러한 종류의 측정에 있어 보통의 방법은 세포 이미징입니다. 
세포의 다른 부분들이 색칠이 칠해져서 세포의 위치가 결정될 수 있습니다.

예를들어, 세포 다섯개가 있는 이미지의 위 패널에서 녹색은 세포 경계를 의미하지만 (cytoskeleton 이라고 하는 염색) 청색은 세포 핵을 보여줍니다.

<img src="img/cells.png" width="70%" style="display: block; margin: auto;" />

이러한 색깔을 이용해서 이미지 안의 세포는 _세그멘트하여 (segmented, 경계를 잡아)_ 어떤 픽셀이 어떤 세포에 속하는지 알아낼 수 있습니다. 
이 과정이 잘 된다면, 세포가 다양한 방법으로 측정이 되어 생물학 연구에 있어 중요할 수 있습니다. 
세포 모양이 중요한 경우가 있어 크기나 "장방형 모양"과 같은 특징들을 요약하는데 다양한 수학적 도구가 사용됩니다. 

아래 패널은 세그멘테이션 결과를 보여줍니다. 
1 번과 5 번 세포는 꽤 잘 세그멘트되었습니다. 
하지만, 3 번, 4 번 세포는 세그멘테이션이 잘 되지 않았기 때문에 뭉쳐져 있습니다. 
세그멘테이션이 잘 되지 않으면, 데이터 오염이 됩니다; 생물학자가 세포의 모양이나 크기를 분석할 때, 데이터가 정확하지 않고 잘못된 결론을 도출하게 됩니다.

세포 기반 실험이 다루는 세포 개수는 수백만 개에 이르므로, 이들을 모두 시각적으로 살펴보는 것은 불가능합니다. 
대신, 서브샘플을 생성하여 전문가가 잘못 세그멘트됨 (`PS`), 잘 세그멘트됨 (`WS`) 중 하나로 수동으로 라벨할 수 있습니다. 
이러한 라벨을 정확하게 예측할 수 있으면, 잘못 세그멘트된 것 같은 세포들을 필터링하여 대량의 데이터가 개선될 수 있습니다. 


### 세포 데이터 돌아가기

`cells` 데이터에는 2019 개 세포의 `class` 라벨이 있습니다 &mdash; 각 세포는 잘못 세그멘트됨 (`PS`), 잘 세그멘트됨 (`WS`) 중 하나로 라벨링 됩니다. 각 세포는 자동 이미지 분석 측정값들에 기반하여 총 56 개의 설명변수가 있습니다. 
예를 들어, `avg_inten_ch_1` 는 핵에 포함된 데이터의 평균강도이고, `area_ch_1` 은 세포의 총 크기, 등입니다. (몇몇 설명변수는 의미가 파악이 안됨)


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

클래스 비율은 다소 불균형입니다; 잘 세그멘트된 세포들보다 잘못 세그멘트된 세포들이 더 많습니다. 


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

이전의 [*레시피로 데이터 전처리하기*](/start/recipes/#data-split) 장에서 데이터 나누기부터 시작했었습니다. 모델링 프로젝트를 시작할 때, 보통 [데이터셋을 두 부분으로 분리](https://bookdown.org/max/FES/data-splitting.html)부터 합니다: 

 * _트레이닝셋_ 은 파라미터를 추정하고, 모델과 피쳐엔지니어링 기술을 비교하고, 모델을 튜닝하는 등에 이용됩니다.

 * _테스트셋_ 은 프로젝트 마지막에 사용되는데, 이 시점에서는 심각하게 고려하는 모델이 한개나 두개 정도여야 합니다. 최종 모델 성능측정을 위한 unbiased source 로 사용됩니다.

데이터를 이렇게 나누는 법은 여러 방법이 있습니다. 
가장 일반적인 방법은 랜덤샘플을 이용하는 것입니다. 데이터 4분의 1이 테스트셋으로 분리한다고 가정합니다. 
랜덤샘플링은 25% 를 랜덤하게 선택하여 테스트셋을 만들고, 나머지를 트레이닝셋으로 사용합니다. [rsample](https://tidymodels.github.io/rsample/) 패키지를 사용하여 할 수 있습니다. 

랜덤 샘플링은 랜덤넘버를 사용하기 때문에, 랜덤넘버 씨드를 설정하는 것이 중요합니다. 랜덤넘버는 (필요시) 나중에 랜덤넘버를 재현할 수 있게 해 줍니다. 

함수 `rsample::initial_split()` 은 원데이터를 입력으로, 어떻게 분리하는지에 대한 정보를 저장합니다. 
원 분석에서, 저자들은 트레이닝/테스트셋을 만들었고, 이 정보를 `case` 열에 저장했습니다. 
나눈 방법을 보여주기 위해, 이 `case` 열을 제거한 뒤 다시 분리를 합니다:


```r
set.seed(123)
cell_split <- initial_split(cells %>% select(-case), 
                            strata = class)
```

여기서 [`strata` 인수](https://tidymodels.github.io/rsample/reference/initial_split.html) 를 통해, 층화분리를 수행합니다. 
우리 `class` 변수가 불균형을 보였지만, 우리 트레이닝과 테스트셋은 잘못/잘 세그멘트된 세포의 비율을 원데이터와 대략 같게 유지하게 해 줍니다. 
`initial_split` 을 한 후 `training()` 과 `testing()` 함수들은 실제 데이터셋을 반환합니다.


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

[랜덤포레스트(random forest) 모델](https://en.wikipedia.org/wiki/Random_forest) 은 [decision tree](https://en.wikipedia.org/wiki/Decision_tree) 의 [앙상블](https://en.wikipedia.org/wiki/Ensemble_learning) 입니다. 
서로 약간 다른 트레이닝셋에 기반하여 많은 수의 decision tree 모델이 생성됩니다. 
적합과정에서는 decision tree 가 최대한 서로 다양하게 만들어지길 유도합니다.
트리의 집합은 random forest 모델로 조합되고, 새로운 샘플이 예측될 때, 각 트리로 부터의 투표가 최종 예측값을 계산하는데 사용됩니다. 
우리의 `cells` 예시 데이터의 `class` 와 같은 범주형 종속변수에 대해, random forest 의 모든 트리를 통틀어 가장 많은 투표를 받은 모델이 새로운 샘플의 예측 클래스를 결정합니다. 

Random Forest 모델의 장점 중 하나는 유지에 손이 거의 들지 않는다는 것입니다. 
데이터 전처리를 할 필요가 거의 없고, 기본값 파라미터들이 괜찮은 결과를 제공합니다. 
따라서 우리는 `cells` 데이터를 위해 레시피를 생성하지는 않을 것입니다. 

Random Forest 라는 이 앙상블 모델의 트리 개수는 많아야 하고 (수천), 이로 인해 모델을 계산하는데 꽤 시간이 걸립니다.

[parsnip](https://tidymodels.github.io/parsnip/) 패키지를 [ranger](https://cran.r-project.org/web/packages/ranger/index.html) 엔진과 함께 사용하여 랜덤포레스트 모델을 적합해 봅시다. 우리가 생성하고 싶은 모델을 우선 정의합니다:


```r
rf_mod <- 
  rand_forest(trees = 1000) %>% 
  set_engine("ranger") %>% 
  set_mode("classification")
```

위의 parsnip 모델 객체부터 시작하여, `fit()` 함수를 모델 공식과 함께 사용할 수 있습니다. 
Random Forest 모델은 랜덤 넘버를 사용하기 때문에, 계산에 앞서 시드를 한번 더 설정합니다: 


```r
set.seed(234)
rf_fit <- 
  rf_mod %>% 
  fit(class ~ ., data = cell_train)
rf_fit
#> parsnip model object
#> 
#> Fit time:  2.2s 
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

새롭게 만들어진 `rf_fit` 객체는 트레이닝 데이터셋에서 훈련된 적합된 모델입니다. 


## 성능 추정하기 {#performance}

모델링 프로젝트동안, 우리는 다양한 모델을 생성할 수 있습니다. 
이들 중 선택하기 위해 모델의 성능 통계량들을 측정하여 고려해야 합니다. 
이 장의 예에서, 사용할 수 있는 선택지들은 다음과 같습니다:

 * Receiver Operating Characteristic (ROC) 커브의 아래 면적
 
 * 종합 분류 정확도 (accuracy).
 
ROC 커브는 클래스 확률 추정값을 사용하여 잠재 확률 컷오프의 전체셋을 통해 성능 감도를 제공합니다. Hard class 예측값은 각 세포마다 `PS`, `WS` 를 예측했는지를 알려줍니다. 
하지만, 이러한 예측 뒤에, 모델은 실제로는 확률을 측정합니다. 
잘못 세그멘트된 것으로 분류하기 위해 50% 확률 컷오프를 사용합니다. 

[yardstick 패키지](https://tidymodels.github.io/yardstick/) 에는 이러한 두 측정값을 계산하는 함수, `roc_auc()` 와 `accuracy()` 가 있습니다. 

처음 보아서는 이러한 통계량을 계산하기 위해 트레이닝 셋 데이터를 사용하는 것이 좋아 보입니다. (이는 사실 매우 나쁜 생각입니다.) 이렇게 했을때 어떤 일이 일어나는지 살펴봅시다. 트레이닝셋에 기반하여 성능을 측정하기 위해 `predict()` 메소드를 호출하여 두 종류의 예측 (즉, 확률과 hard class 예측) 을 구합니다. 


```r
rf_training_pred <- 
  predict(rf_fit, cell_train) %>% 
  bind_cols(predict(rf_fit, cell_train, type = "prob")) %>% 
  # Add the true outcome data back in
  bind_cols(cell_train %>% 
              select(class))
```

yardstick 함수들을 사용했을 때, 이 모델은 엄청난 결과를 보여주는데, 결과가 너무 엄청나서 의심이 생기기 시작할 것입니다: 


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

이 모델 성능이 매우 좋기 때문에, 테스트셋으로 진행합니다. 
결과가 나쁘지는 않지만, 트레이닝셋 예측성능에 기반하여 기대했던 것보다는 좋지 않습니다.


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

이 섹션에서 보이는 것 같이 트레이닝셋 통계량이 실제와 다르게 긍정적으로 나오는 것에는 여러 이유가 있습니다. 

* 랜덤포레스트, 뉴럴 네트워크, 다른 블랙박스 방법들 같은 모델들은 트레이닝셋을 본질적으로 암기할 수 있습니다. 같은 셋을 다시 예측하면 항상 거의 완벽한 결과를 제공할 수 밖에 없습니다. 

* 트레이닝셋은 성능의 좋은 심판자가 될 역량이 없습니다. 정보가 독립되지 않습니다; 트레이닝셋을 예측하는 것은 모델이 이미 알고 무엇을 알고 있는지를 반영할 뿐입니다. 

두 번째 방법을 더 잘 이해하기 위해 가르치는 것에서 비유를 생각해 보세요. 학급에 시험을 치룬다고 가정한후 정답을 주고, 같은 시험을 치룹니다. _두번째_ 시험에서 학생들 성적은 과목에 대해 얼마나 알고 있는지를 정확하게 반영하지 않습니다; 이 점수들은 첫번째 시험의 결과보다 아마 더 높기만 할 것입니다. 


## 리샘플링을 이용한 문제해결 {#resampling}

cross-validation 과 bootstrap 과 같은 리샘플링방법은 실험적 시뮬레이션 시스템입니다. 
이들은 앞서 논의한 training/testing 분할과 유사하게 데이터셋들을 생성합니다. 
일부 서브셋은 모델을 생성하는데 사용되고 다른 서브셋은 성능을 측정하는데 사용됩니다.
리샘플링은 항상 _트레이닝셋_ 과 사용됩니다. 
[Kuhn and Johnson (2019)](https://bookdown.org/max/FES/resampling.html) 의 스케매틱에서는 리샘플링 방법에서 데이터들이 어떻게 사용되는지 보여줍니다:

<img src="img/resampling.svg" width="85%" style="display: block; margin: auto;" />

이 다이어그램의 첫번째 수준에서, `rsample::initial_split()` 을 사용할 때 일어나는 일을 볼 수 있는데, 원 데이터를 트레이닝과 테스트셋으로 분할합니다. 
그 후 트레이닝셋이 리샘플링을 위해 선택되고 테스트셋은 보존됩니다.

이 예에서는 10-폴드 cross-validation (CV) 를 사용합니다. 
트레이닝셋에 있는 1514 개의 세포관측값들을 "폴드" 라고 부르는 같은 크기의 10 개 그룹으로 랜덤하게 할당합니다.
리샘플링의 첫번째 반복에서, 약 151 개의 세포들로 이루어진 첫번째 폴드를 따로 떼어 성능 측정을 위해 사용합니다. 
이 데이터는 테스트셋과 유사하지만, 혼동을 피하기 위해, tidymodels 프레임워크에서 _평가셋(assessment set)_ 으로 부릅니다. 

데이터의 나머지 90% (약 1362 개의 세포) 가 모델을 적합하기 위해 사용됩니다.
트레이닝셋과는 조금 다른데, tidymodel 에서는 이를 _분석셋(analysis set)_ 으로 부릅니다. 
분석셋을 이용하여 훈련된 모델은 평가셋을 이용하여 예측값을 생성하고, 이 예측값에 기반하여 평가통계량이 계산됩니다. 

이 예에서, 10-폴드 CV 는 폴드를 바꿔가며 진행하고, 매번 다른 10% 를 모델 평가를 위해 남겨놓습니다.
마지막에 모델 프로세스에서 사용하지 않은 10 개의 데이터셋에서 생성된 성능통계량이 10 개 생깁니다.
세포 예에서는 정확도 10 개와 area under the ROC curve 10 개가 생깁니다. 
모델도 10 개가 생성되었지만, 더 이상 사용되지 않습니다; 이 폴드에서 훈련된 모델은 사용되지 않는데, 이들은 성능 지표를 계산할 목적으로만 생성했기 때문입니다.



모델의 마지막 리샘플링 추정값은 성능 통계량값들의 **평균**입니다. 
예를 들어, 우리 데이터의 경우 결과는 다음과 같습니다:

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

리샘플링 통계량으로부터 계산한 랜덤포레스트 모델의 최적 성능추정값은 area under the ROC curve 는 0.904 이고, 정확도는 0.904 입니다.

리샘플링 통계량은 트레이닝셋 전체를 직접 예측하지 _않고_, 모델 성능을 측정할 수 있는 효율적인 방법입니다. 


## 리샘플링으로 모델 적합 {#fit-resamples}

이 결과를 생성하기 위한 첫번째 단계는 rsample 을 이용해서 리샘플링 객체를 생성하는 것입니다. 
rsample 에는 [몇 개의 리샘플링 방법들](https://tidymodels.github.io/rsample/reference/index.html#section-resampling-methods)이 구현되어 있습니다; `vfold_cv()` 를 이용하여 cross-validation fold 를 생성할 수 있습니다:


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

`splits` 리스트-열에는 각 행이 분석셋에 속하는지, 평가셋에 속하는지에 관한 정보가 있습니다. 
`analysis()` 와 `assessment()` 함수를 이용하여 각 리샘플된 데이터를 추출할 수 있습니다. 

하지만, tune 패키지에는 성능을 측정할 목적으로 모델을 리샘플하기 위해, 필요한 계산을 하는 고차원 함수들이 있습니다.
리샘플링 위해 객체를 만드는 몇몇 선택지가 있습니다:

+ 공식이나 [레시피](/start/recipes/)를 이용하여 전처리된 모델 스펙을 리샘플하기 

+ 모델 스펙과 공식/레시피를 함께 묶은 [`workflow()`](https://tidymodels.github.io/workflows/)를 리샘플하기

이 예에서는 레시피를 사용하지 않기 때문에, random forest 모델과 공식을 묶은 `workflow()` 를 리샘플합니다. 
이 옵션 중 어떤걸 사용하던지에 관계없이, `fit_resamples()` 의 문법은 `fit()` 과 매우 유사합니다:


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

결과는 추가 열이 있는 `folds` 결과와 매우 유사합니다. 
`.metrics` 열은 10 개의 평가셋에서 생성된 성능 통계량을 포함합니다. 
수동으로 unnest 할 수도 있지만, tune 패키지에는 이러한 데이터를 추출할 수 있는 편리한 함수들이 많습니다:


```r
collect_metrics(rf_fit_rs)
#> # A tibble: 2 × 6
#>   .metric  .estimator  mean     n std_err .config             
#>   <chr>    <chr>      <dbl> <int>   <dbl> <chr>               
#> 1 accuracy binary     0.832    10 0.00952 Preprocessor1_Model1
#> 2 roc_auc  binary     0.904    10 0.00610 Preprocessor1_Model1
```

이제 accuracy 와 AUC 를 생각해봅시다. 
이 섹션의 앞에서 잘못 가이드를 받아 했을 때보다 더 현실적 (즉, 낮음) 입니다. 
이 데이터셋에 다른 모델을 시도하고 싶다면, 모델 사이에 선택하기 위해 리샘플링을 사용하여 계산된 성능 지표들을 더 자신있게 비교해야할 것입니다. 
또한, 프로젝트 마지막에 우리 테스트셋으로 돌아가서 최종 모델 성능을 추정할 것을 기억하십시오. 
리샘플링을 사용하기 시작하기 전에 이미 한번 이를 보았지만, 결과를 다시 봅시다:


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

테스트셋에서 성능 지표는 처음 ("잘못된 생각") 시도보다 리샘플링을 사용하여 계산한 성능지표에 훨씬 더 가깝습니다. 
리샘플링을 하면 우리 모델이 새로운 데이터에 성능이 얼마나 될 것인지를 시뮬레이트할 수 있고, 테스트셋을 사용하면 우리 모델 성능에 최종, 그리고 바이어스가 없는 확인을 할 수 있습니다.


## 세션정보


```
#> ─ Session info  💳  🤵🏿  🇵🇬   ───────────────────────────────────────
#>  hash: credit card, person in tuxedo: dark skin tone, flag: Papua New Guinea
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
#>  date     2022-03-10
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  modeldata  * 0.1.1   2021-07-14 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  ranger     * 0.13.1  2021-07-14 [1] CRAN (R 4.1.0)
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
