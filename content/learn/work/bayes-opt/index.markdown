---
title: "분류 모델의 반복적 베이지언 최적화"
tags: [tune, dials, parsnip, recipes, workflows]
categories: [model tuning]
type: learn-subsection
weight: 3
description: | 
  반복적 탐색의 베이지언 최적화를 사용한 최적 모델 하이퍼파라미터 식별하기.
---


  


## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: kernlab, modeldata, themis, and tidymodels.

모델 튜닝의 많은 예제들은 [grid search](/learn/work/tune-svm/)에 집중합니다. 이 방법에 관해, 모든 후보 튜닝 파라미터 조합들은 평가 이전에 정의됩니다. 대안적인 방법으로 _반복탐색(iterative search)_ 을 사용하여 기존 튜닝파라미터 결과를 분석하고 어떤 튜닝 파라미터를 다음에 시도해야하는지 _예측_ 하는 방법도 있습니다. 

다양한 반복탐색 방법이 있는데 이 장의 주제는 _베이지언최적화_ 입니다. 이 방법에 관한 정보는 다음의 자료들이 도움을 줍니다:

* [_Practical bayesian optimization of machine learning algorithms_](https://scholar.google.com/scholar?hl=en&as_sdt=0%2C7&q=Practical+Bayesian+Optimization+of+Machine+Learning+Algorithms&btnG=) (2012). J Snoek, H Larochelle, and RP Adams. Advances in neural information.  

* [_A Tutorial on Bayesian Optimization for Machine Learning_](https://www.cs.toronto.edu/~rgrosse/courses/csc411_f18/tutorials/tut8_adams_slides.pdf) (2018). R Adams.

 * [_Gaussian Processes for Machine Learning_](http://www.gaussianprocess.org/gpml/) (2006). C E Rasmussen and C Williams.

* [Other articles!](https://scholar.google.com/scholar?hl=en&as_sdt=0%2C7&q="Bayesian+Optimization"&btnG=)


## 세포 세그멘팅 - 계속

튜닝 모델에 관한 이 접근법을 시연하기 위해, 리샘플링에 관한 [시작하기](/start/resampling/) 장의 세포 세그멘테이션 데이터를 다시 살펴봅시다: 


```r
library(tidymodels)
library(modeldata)

# Load data
data(cells)

set.seed(2369)
tr_te_split <- initial_split(cells %>% select(-case), prop = 3/4)
cell_train <- training(tr_te_split)
cell_test  <- testing(tr_te_split)

set.seed(1697)
folds <- vfold_cv(cell_train, v = 10)
```

## 튜닝 스킴

설명변수들이 상당히 상관되어있기 때문에, 레시피를 사용하여 원 설명변수를 주성분 점수로 변환할 수 있습니다. 이 데이터에는 클래스 불균형이 약간 있습니다; 약 64% 의 데이터가 잘못 세그멘트되었습니다. 이를 개선시키기 위해, 데이터는 전처리의 마지막에 다운샘플해서 잘못/잘 세그멘트된 세포가 같은 빈도로 일어나도록 할 것입니다. 레시피를 사용하여 이 모든 전처리를 할 수 있지만, 주성분 개수는 _튜닝_되어서 충분한 (하지만 너무 많지 않은) 데이터 representation 을 가지도록 할 필요가 있을 것입니다.


```r
library(themis)

cell_pre_proc <-
  recipe(class ~ ., data = cell_train) %>%
  step_YeoJohnson(all_predictors()) %>%
  step_normalize(all_predictors()) %>%
  step_pca(all_predictors(), num_comp = tune()) %>%
  step_downsample(class)
```

이 분석에서, 서포트벡터머신을 사용하여 데이터 모델링을 할 것입니다. radial basis function (RBF) 커널을 사용하고 메인 파라미터 ($\sigma$) 를 튜닝해 봅시다. 또한 메인 SVM 파라미터인, 비용값(cost value)도 최적화 될 필요가 있습니다. 


```r
svm_mod <-
  svm_rbf(mode = "classification", cost = tune(), rbf_sigma = tune()) %>%
  set_engine("kernlab")
```


이 레시피와 모델, 두 객체는 [workflows](https://tidymodels.github.io/workflows/) 패키지의 `workflow()` 함수를 이용하여 하나의 객체로 결합될 것입니다; 이 객체는 최적화 과정에서 사용될 것입니다. 


```r
svm_wflow <-
  workflow() %>%
  add_model(svm_mod) %>%
  add_recipe(cell_pre_proc)
```

이 객체로 부터, 어떤 파라미터가 스레이트에 올라와 있어서 튜닝될 것인지에 관한 정보를 추출할 수 있습니다. 파라미터셋은 다음으로 추출됩니다:


```r
svm_set <- parameters(svm_wflow)
svm_set
#> Collection of 3 parameters for tuning
#> 
#>  identifier      type    object
#>        cost      cost nparam[+]
#>   rbf_sigma rbf_sigma nparam[+]
#>    num_comp  num_comp nparam[+]
```

PCA 성분의 개수의 기본값 범위는 이 데이터셋에 좁은 편입니다. 파라미터셋의 구성요소는 `update()` 함수를 사용하여 수정할 수 있습니다. `num_comp` 파라미터를 업데이트해서 1 에서 20 개 성분으로 탐색을 제약해 봅시다. 추가적으로, 이 파라미터의 lower bound 를 0으로 설정하여 원 설명변수 셋도 evaluate 될 수 있게 합니다. (즉, PCA 단계를 전혀 하지 않음):


```r
svm_set <- 
  svm_set %>% 
  update(num_comp = num_comp(c(0L, 20L)))
```

## 순차 튜닝

베이지언 최적화는 새로운 후보 파라미터를 예측하는 모델을 사용하는 순차 방법론입니다. 잠재 파라미터 값을 스코어링할 때, 성능 평균과 분산이 예측됩니다. 이러한 두 통계량을 어떻게 사용할지를 정의하는데 사용되는 전략은 _acquisition function_ 이 정의합니다.

예를들어, 새로운 후보를 스코어링하는 전략 중 하나는 신뢰 범위(bound)를 사용하는 것입니다. 정확도가 최적화되고 있다고 합시다. 우리가 최적화하고 싶은 지표에 관해, lower confidence bound 가 사용됩니다. 표준오차 ($\kappa$ 로 표시) 의 multiplier 는 **exploration** 과 **exploitation** 사이의 트레이드오프를 만드는 데 사용될 수 있는 값입니다.

 * **Exploration** 은 탐색이 테스트되지 않은 공간의 후보들을 고려할 것이라는 것을 의미합니다.

 * **Exploitation** 은 과거 가장 좋은 결과를 얻은 영역에 집중합니다.

베이지언 모델이 예측한 분산은 대부분 공간 분산입니다; 이미 평가된 값과 가깝지 않은 후보에 대해서는 분산이 클 것입니다. 표준오차 multiplier 가 높다면, 탐색 프로세스는 가까운 후보 값들 없는 영역은 피할 가능성이 큽니다.

다른 acquisition function 인, _expected improvement_ 를 사용할 것인데, 이는 현재 가장 좋은 결과에 상대적으로 어떤 후보가 도움을 줄 가능성이 큰지를 결정합니다. 이 함수가 기본값입니다. 이 함수들에 관한 정보는 [acquisition functions 패키지 vignette](https://tidymodels.github.io/tune/articles/acquisition_functions.html) 에 있습니다. 


```r
set.seed(12)
search_res <-
  svm_wflow %>% 
  tune_bayes(
    resamples = folds,
    # To use non-default parameter ranges
    param_info = svm_set,
    # Generate five at semi-random to start
    initial = 5,
    iter = 50,
    # How to measure performance?
    metrics = metric_set(roc_auc),
    control = control_bayes(no_improve = 30, verbose = TRUE)
  )
#> 
#> >  Generating a set of 5 initial parameter results
#> ✓ Initialization complete
#> 
#> Optimizing roc_auc using the expected improvement
#> 
#> ── Iteration 1 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8764 (@iter 0)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00386, rbf_sigma=0.00513, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8797 (+/-0.0108)
#> 
#> ── Iteration 2 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8797 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.245, rbf_sigma=0.00334, num_comp=2
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7966 (+/-0.0103)
#> 
#> ── Iteration 3 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8797 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=25.8, rbf_sigma=0.00543, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8881 (+/-0.00921)
#> 
#> ── Iteration 4 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8881 (@iter 3)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.403, rbf_sigma=0.944, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.387 (+/-0.0833)
#> 
#> ── Iteration 5 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8881 (@iter 3)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0315, rbf_sigma=0.00228, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8806 (+/-0.0114)
#> 
#> ── Iteration 6 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8881 (@iter 3)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=24.8, rbf_sigma=0.0041, num_comp=17
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8882 (+/-0.00987)
#> 
#> ── Iteration 7 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8882 (@iter 6)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=27.5, rbf_sigma=0.00924, num_comp=16
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8883 (+/-0.0105)
#> 
#> ── Iteration 8 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8883 (@iter 7)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=5.6, rbf_sigma=0.00774, num_comp=14
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8894 (+/-0.0109)
#> 
#> ── Iteration 9 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8894 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=6.12, rbf_sigma=0.0063, num_comp=17
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.885 (+/-0.0103)
#> 
#> ── Iteration 10 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8894 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=16.6, rbf_sigma=0.00343, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8869 (+/-0.00985)
#> 
#> ── Iteration 11 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8894 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=19.5, rbf_sigma=0.0082, num_comp=15
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8943 (+/-0.0101)
#> 
#> ── Iteration 12 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=15.1, rbf_sigma=1.09e-10, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3451 (+/-0.116)
#> 
#> ── Iteration 13 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=7.19, rbf_sigma=0.00528, num_comp=15
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8868 (+/-0.0107)
#> 
#> ── Iteration 14 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=11.8, rbf_sigma=0.00143, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8811 (+/-0.0112)
#> 
#> ── Iteration 15 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=23.9, rbf_sigma=0.015, num_comp=15
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8853 (+/-0.0123)
#> 
#> ── Iteration 16 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=29.4, rbf_sigma=0.00841, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8823 (+/-0.0105)
#> 
#> ── Iteration 17 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00117, rbf_sigma=0.0112, num_comp=14
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8771 (+/-0.0119)
#> 
#> ── Iteration 18 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8943 (@iter 11)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=16.7, rbf_sigma=0.0137, num_comp=10
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.9 (+/-0.00986)
#> 
#> ── Iteration 19 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9 (@iter 18)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=31.9, rbf_sigma=0.0147, num_comp=8
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8985 (+/-0.0101)
#> 
#> ── Iteration 20 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9 (@iter 18)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=8.72, rbf_sigma=0.0184, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.9021 (+/-0.0101)
#> 
#> ── Iteration 21 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 20)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=17.4, rbf_sigma=0.0158, num_comp=10
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.9005 (+/-0.0099)
#> 
#> ── Iteration 22 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 20)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=20.4, rbf_sigma=0.0214, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.9002 (+/-0.0102)
#> 
#> ── Iteration 23 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 20)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=13.8, rbf_sigma=0.0145, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.9018 (+/-0.0101)
#> 
#> ── Iteration 24 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 20)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=14.8, rbf_sigma=0.017, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.9021 (+/-0.00998)
#> 
#> ── Iteration 25 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=17.2, rbf_sigma=0.0083, num_comp=10
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8986 (+/-0.00973)
#> 
#> ── Iteration 26 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=20, rbf_sigma=0.018, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.9011 (+/-0.0102)
#> 
#> ── Iteration 27 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0185, rbf_sigma=0.0151, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8774 (+/-0.0123)
#> 
#> ── Iteration 28 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00426, rbf_sigma=0.0181, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8841 (+/-0.0108)
#> 
#> ── Iteration 29 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00102, rbf_sigma=0.00959, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8832 (+/-0.011)
#> 
#> ── Iteration 30 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.983, rbf_sigma=0.0204, num_comp=10
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8917 (+/-0.0106)
#> 
#> ── Iteration 31 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=14.2, rbf_sigma=0.0104, num_comp=8
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8977 (+/-0.01)
#> 
#> ── Iteration 32 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=14.5, rbf_sigma=0.0114, num_comp=11
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8971 (+/-0.00976)
#> 
#> ── Iteration 33 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=19.4, rbf_sigma=0.0126, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.9017 (+/-0.00997)
#> 
#> ── Iteration 34 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=11.8, rbf_sigma=0.0207, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.902 (+/-0.00981)
#> 
#> ── Iteration 35 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=12.6, rbf_sigma=0.0164, num_comp=8
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8987 (+/-0.0102)
#> 
#> ── Iteration 36 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=22.7, rbf_sigma=0.000423, num_comp=1
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7725 (+/-0.0106)
#> 
#> ── Iteration 37 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=9.21, rbf_sigma=0.0192, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.9017 (+/-0.00992)
#> 
#> ── Iteration 38 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00227, rbf_sigma=0.0278, num_comp=15
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8828 (+/-0.0113)
#> 
#> ── Iteration 39 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0012, rbf_sigma=0.000867, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3449 (+/-0.116)
#> 
#> ── Iteration 40 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.118, rbf_sigma=0.00525, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8806 (+/-0.0112)
#> 
#> ── Iteration 41 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=25.1, rbf_sigma=0.00223, num_comp=17
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8811 (+/-0.0108)
#> 
#> ── Iteration 42 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.892, rbf_sigma=0.00268, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8818 (+/-0.0116)
#> 
#> ── Iteration 43 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0108, rbf_sigma=0.00733, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8756 (+/-0.0121)
#> 
#> ── Iteration 44 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.061, rbf_sigma=0.00356, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.881 (+/-0.0113)
#> 
#> ── Iteration 45 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00135, rbf_sigma=0.0218, num_comp=2
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7966 (+/-0.0104)
#> 
#> ── Iteration 46 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0476, rbf_sigma=0.0248, num_comp=17
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8809 (+/-0.0113)
#> 
#> ── Iteration 47 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00158, rbf_sigma=0.0689, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8784 (+/-0.0101)
#> 
#> ── Iteration 48 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00171, rbf_sigma=0.0337, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8836 (+/-0.0104)
#> 
#> ── Iteration 49 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=29.2, rbf_sigma=0.000104, num_comp=15
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.875 (+/-0.0122)
#> 
#> ── Iteration 50 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.9021 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=30.2, rbf_sigma=4.34e-05, num_comp=2
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7965 (+/-0.0104)
```

출력되는 티블은 반복수를 위한 열이 추가된 rsample 객체가 열로 있는 스택된 집합입니다:


```r
search_res
#> # Tuning results
#> # 10-fold cross-validation 
#> # A tibble: 510 × 5
#>    splits             id     .metrics         .notes           .iter
#>    <list>             <chr>  <list>           <list>           <int>
#>  1 <split [1362/152]> Fold01 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  2 <split [1362/152]> Fold02 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  3 <split [1362/152]> Fold03 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  4 <split [1362/152]> Fold04 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  5 <split [1363/151]> Fold05 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  6 <split [1363/151]> Fold06 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  7 <split [1363/151]> Fold07 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  8 <split [1363/151]> Fold08 <tibble [5 × 7]> <tibble [0 × 1]>     0
#>  9 <split [1363/151]> Fold09 <tibble [5 × 7]> <tibble [0 × 1]>     0
#> 10 <split [1363/151]> Fold10 <tibble [5 × 7]> <tibble [0 × 1]>     0
#> # … with 500 more rows
```

그리드 탐색에서와 같이, 리샘플 결과들을 요약할 수 있습니다:


```r
estimates <- 
  collect_metrics(search_res) %>% 
  arrange(.iter)

estimates
#> # A tibble: 55 × 10
#>        cost  rbf_sigma num_comp .metric .estimator  mean     n std_err .config  
#>       <dbl>      <dbl>    <int> <chr>   <chr>      <dbl> <int>   <dbl> <chr>    
#>  1  0.00207    1.56e-5       10 roc_auc binary     0.345    10 0.114   Preproce…
#>  2  0.348      4.43e-2        1 roc_auc binary     0.773    10 0.0106  Preproce…
#>  3 15.5        1.28e-7       20 roc_auc binary     0.345    10 0.116   Preproce…
#>  4  1.45       2.04e-3       15 roc_auc binary     0.876    10 0.0121  Preproce…
#>  5  0.0304     6.41e-9        5 roc_auc binary     0.345    10 0.113   Preproce…
#>  6  0.00386    5.13e-3       19 roc_auc binary     0.880    10 0.0108  Iter1    
#>  7  0.245      3.34e-3        2 roc_auc binary     0.797    10 0.0103  Iter2    
#>  8 25.8        5.43e-3       20 roc_auc binary     0.888    10 0.00921 Iter3    
#>  9  0.403      9.44e-1       20 roc_auc binary     0.387    10 0.0833  Iter4    
#> 10  0.0315     2.28e-3       20 roc_auc binary     0.881    10 0.0114  Iter5    
#> # … with 45 more rows, and 1 more variable: .iter <int>
```

초기 후보값셋의 가장좋은 성능은 `AUC = 0.876 ` 였습니다. 가장 좋은 결과는 반복 24 에서 얻어졌고, 이 때 AUC 값은 0.902 이었습니다. 가장 결과가 좋은 다섯 개는:


```r
show_best(search_res, metric = "roc_auc")
#> # A tibble: 5 × 10
#>    cost rbf_sigma num_comp .metric .estimator  mean     n std_err .config .iter
#>   <dbl>     <dbl>    <int> <chr>   <chr>      <dbl> <int>   <dbl> <chr>   <int>
#> 1 14.8     0.0170        9 roc_auc binary     0.902    10 0.00998 Iter24     24
#> 2  8.72    0.0184        9 roc_auc binary     0.902    10 0.0101  Iter20     20
#> 3 11.8     0.0207        9 roc_auc binary     0.902    10 0.00981 Iter34     34
#> 4 13.8     0.0145        9 roc_auc binary     0.902    10 0.0101  Iter23     23
#> 5 19.4     0.0126        9 roc_auc binary     0.902    10 0.00997 Iter33     33
```

A plot of the search iterations can be created via:


```r
autoplot(search_res, type = "performance")
```

<img src="figs/bo-plot-1.svg" width="672" />

There are many parameter combinations have roughly equivalent results. 

How did the parameters change over iterations? 



```r
autoplot(search_res, type = "parameters") + 
  labs(x = "Iterations", y = NULL)
```

<img src="figs/bo-param-plot-1.svg" width="864" />




## Session information


```
#> ─ Session info  ㊗️  👎🏾  💷   ───────────────────────────────────────
#>  hash: Japanese “congratulations” button, thumbs down: medium-dark skin tone, pound banknote
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
#>  date     2022-01-10
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.10  2021-10-31 [1] CRAN (R 4.1.0)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  kernlab    * 0.9-29  2019-11-12 [1] CRAN (R 4.1.0)
#>  modeldata  * 0.1.1   2021-07-14 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
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
 
