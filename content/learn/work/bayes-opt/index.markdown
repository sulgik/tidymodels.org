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
#> i Current best:		roc_auc=0.8775 (@iter 0)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0142, rbf_sigma=0.0051, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8795 (+/-0.0109)
#> 
#> ── Iteration 2 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.56, rbf_sigma=0.00327, num_comp=1
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7725 (+/-0.0106)
#> 
#> ── Iteration 3 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00405, rbf_sigma=1.07e-08, num_comp=11
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3454 (+/-0.114)
#> 
#> ── Iteration 4 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=8.93, rbf_sigma=1.71e-08, num_comp=9
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.346 (+/-0.114)
#> 
#> ── Iteration 5 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=6.48, rbf_sigma=7.8e-07, num_comp=3
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.865 (+/-0.0127)
#> 
#> ── Iteration 6 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00256, rbf_sigma=0.0101, num_comp=7
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8756 (+/-0.0119)
#> 
#> ── Iteration 7 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.153, rbf_sigma=6.85e-07, num_comp=13
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3463 (+/-0.114)
#> 
#> ── Iteration 8 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8795 (@iter 1)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=1.83, rbf_sigma=0.00601, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8803 (+/-0.0104)
#> 
#> ── Iteration 9 ───────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=10.5, rbf_sigma=3.7e-10, num_comp=12
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3457 (+/-0.114)
#> 
#> ── Iteration 10 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00127, rbf_sigma=1.12e-07, num_comp=2
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3906 (+/-0.0924)
#> 
#> ── Iteration 11 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=4.09, rbf_sigma=0.000619, num_comp=8
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8743 (+/-0.0122)
#> 
#> ── Iteration 12 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=22.2, rbf_sigma=8.88e-06, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8717 (+/-0.0118)
#> 
#> ── Iteration 13 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0342, rbf_sigma=0.0226, num_comp=13
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8781 (+/-0.012)
#> 
#> ── Iteration 14 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=23.7, rbf_sigma=2.12e-06, num_comp=1
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7725 (+/-0.0106)
#> 
#> ── Iteration 15 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=6.12, rbf_sigma=9.13e-06, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.865 (+/-0.0118)
#> 
#> ── Iteration 16 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00206, rbf_sigma=0.00305, num_comp=11
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8746 (+/-0.0123)
#> 
#> ── Iteration 17 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.381, rbf_sigma=6.13e-07, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3569 (+/-0.111)
#> 
#> ── Iteration 18 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=19.1, rbf_sigma=0.000136, num_comp=10
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.875 (+/-0.012)
#> 
#> ── Iteration 19 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8803 (@iter 8)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00499, rbf_sigma=0.0141, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8839 (+/-0.0106)
#> 
#> ── Iteration 20 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8839 (@iter 19)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=5.48, rbf_sigma=0.00215, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.882 (+/-0.0104)
#> 
#> ── Iteration 21 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8839 (@iter 19)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0106, rbf_sigma=0.0116, num_comp=3
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8662 (+/-0.0128)
#> 
#> ── Iteration 22 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8839 (@iter 19)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=28.7, rbf_sigma=0.000625, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8947 (+/-0.00961)
#> 
#> ── Iteration 23 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8947 (@iter 22)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=26.4, rbf_sigma=0.00012, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8823 (+/-0.0106)
#> 
#> ── Iteration 24 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8947 (@iter 22)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=14.5, rbf_sigma=0.00104, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8955 (+/-0.00965)
#> 
#> ── Iteration 25 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=7.73, rbf_sigma=3.27e-06, num_comp=16
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8745 (+/-0.012)
#> 
#> ── Iteration 26 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0588, rbf_sigma=0.874, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3965 (+/-0.0811)
#> 
#> ── Iteration 27 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=29.9, rbf_sigma=0.0116, num_comp=2
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7969 (+/-0.00997)
#> 
#> ── Iteration 28 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=5.34, rbf_sigma=1.56e-06, num_comp=1
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7725 (+/-0.0106)
#> 
#> ── Iteration 29 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=12.6, rbf_sigma=1.9e-05, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8732 (+/-0.0121)
#> 
#> ── Iteration 30 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=17.7, rbf_sigma=7.96e-07, num_comp=19
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8772 (+/-0.0112)
#> 
#> ── Iteration 31 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=18.8, rbf_sigma=8.22e-06, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8776 (+/-0.0116)
#> 
#> ── Iteration 32 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0102, rbf_sigma=0.0525, num_comp=4
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8688 (+/-0.0128)
#> 
#> ── Iteration 33 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8955 (@iter 24)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=3.18, rbf_sigma=0.0155, num_comp=14
#> i Estimating performance
#> ✓ Estimating performance
#> ♥ Newest results:	roc_auc=0.8957 (+/-0.01)
#> 
#> ── Iteration 34 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0115, rbf_sigma=0.00146, num_comp=6
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8744 (+/-0.0117)
#> 
#> ── Iteration 35 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00562, rbf_sigma=0.00322, num_comp=4
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8647 (+/-0.0126)
#> 
#> ── Iteration 36 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=24.4, rbf_sigma=3.63e-05, num_comp=1
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7725 (+/-0.0106)
#> 
#> ── Iteration 37 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00127, rbf_sigma=0.0348, num_comp=10
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8808 (+/-0.0112)
#> 
#> ── Iteration 38 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=28.3, rbf_sigma=0.000263, num_comp=1
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.7725 (+/-0.0106)
#> 
#> ── Iteration 39 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.15, rbf_sigma=0.000832, num_comp=17
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8736 (+/-0.0123)
#> 
#> ── Iteration 40 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=3.44, rbf_sigma=8.28e-05, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8732 (+/-0.0121)
#> 
#> ── Iteration 41 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=2.6, rbf_sigma=0.0103, num_comp=13
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8883 (+/-0.0104)
#> 
#> ── Iteration 42 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00515, rbf_sigma=0.0294, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8741 (+/-0.0124)
#> 
#> ── Iteration 43 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00357, rbf_sigma=0.000663, num_comp=2
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3905 (+/-0.0924)
#> 
#> ── Iteration 44 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.166, rbf_sigma=0.00125, num_comp=8
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8736 (+/-0.0122)
#> 
#> ── Iteration 45 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=1.34, rbf_sigma=0.000972, num_comp=20
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8806 (+/-0.0114)
#> 
#> ── Iteration 46 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00114, rbf_sigma=0.113, num_comp=0
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.3478 (+/-0.114)
#> 
#> ── Iteration 47 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00111, rbf_sigma=0.0217, num_comp=3
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8667 (+/-0.0128)
#> 
#> ── Iteration 48 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.385, rbf_sigma=0.0156, num_comp=17
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8848 (+/-0.0107)
#> 
#> ── Iteration 49 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.0365, rbf_sigma=0.00154, num_comp=18
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8736 (+/-0.0121)
#> 
#> ── Iteration 50 ──────────────────────────────────────────────────────
#> 
#> i Current best:		roc_auc=0.8957 (@iter 33)
#> i Gaussian process model
#> ✓ Gaussian process model
#> i Generating 5000 candidates
#> i Predicted candidates
#> i cost=0.00395, rbf_sigma=0.00626, num_comp=16
#> i Estimating performance
#> ✓ Estimating performance
#> ⓧ Newest results:	roc_auc=0.8764 (+/-0.0119)
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
#>  1  0.00207    1.56e-5       10 roc_auc binary     0.345    10  0.114  Preproce…
#>  2  0.348      4.43e-2        1 roc_auc binary     0.773    10  0.0106 Preproce…
#>  3 15.5        1.28e-7       20 roc_auc binary     0.346    10  0.115  Preproce…
#>  4  1.45       2.04e-3       15 roc_auc binary     0.877    10  0.0119 Preproce…
#>  5  0.0304     6.41e-9        5 roc_auc binary     0.345    10  0.114  Preproce…
#>  6  0.0142     5.10e-3       19 roc_auc binary     0.879    10  0.0109 Iter1    
#>  7  0.560      3.27e-3        1 roc_auc binary     0.773    10  0.0106 Iter2    
#>  8  0.00405    1.07e-8       11 roc_auc binary     0.345    10  0.114  Iter3    
#>  9  8.93       1.71e-8        9 roc_auc binary     0.346    10  0.114  Iter4    
#> 10  6.48       7.80e-7        3 roc_auc binary     0.865    10  0.0127 Iter5    
#> # … with 45 more rows, and 1 more variable: .iter <int>
```

초기 후보값셋의 가장좋은 성능은 `AUC = 0.877 ` 였습니다. 가장 좋은 결과는 반복 33 에서 얻어졌고, 이 때 AUC 값은 0.896 이었습니다. 가장 결과가 좋은 다섯 개는:


```r
show_best(search_res, metric = "roc_auc")
#> # A tibble: 5 × 10
#>     cost rbf_sigma num_comp .metric .estimator  mean     n std_err .config .iter
#>    <dbl>     <dbl>    <int> <chr>   <chr>      <dbl> <int>   <dbl> <chr>   <int>
#> 1  3.18   0.0155         14 roc_auc binary     0.896    10 0.0100  Iter33     33
#> 2 14.5    0.00104         0 roc_auc binary     0.896    10 0.00965 Iter24     24
#> 3 28.7    0.000625        0 roc_auc binary     0.895    10 0.00961 Iter22     22
#> 4  2.60   0.0103         13 roc_auc binary     0.888    10 0.0104  Iter41     41
#> 5  0.385  0.0156         17 roc_auc binary     0.885    10 0.0107  Iter48     48
```

탐색 반복 플롯은 다음으로 생성할 수 있습니다:


```r
autoplot(search_res, type = "performance")
```

<img src="figs/bo-plot-1.svg" width="672" />

대략 비슷한 결과를 낳는 파라미터 조합이 많이 있습니다.

파라미터들이 반복하면서 어떻게 변화했습니까?



```r
autoplot(search_res, type = "parameters") + 
  labs(x = "Iterations", y = NULL)
```

<img src="figs/bo-param-plot-1.svg" width="864" />




## Session information


```
#> ─ Session info ───────────────────────────────────────────────────────────────
#>  setting  value                       
#>  version  R version 4.0.3 (2020-10-10)
#>  os       macOS Catalina 10.15.7      
#>  system   x86_64, darwin17.0          
#>  ui       X11                         
#>  language (EN)                        
#>  collate  en_US.UTF-8                 
#>  ctype    en_US.UTF-8                 
#>  tz       Asia/Seoul                  
#>  date     2022-01-10                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package    * version date       lib source        
#>  broom      * 0.7.9   2021-07-27 [1] CRAN (R 4.0.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.0.2)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.0.2)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.0.2)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.0.2)
#>  kernlab    * 0.9-29  2019-11-12 [1] CRAN (R 4.0.2)
#>  modeldata  * 0.1.1   2021-07-14 [1] CRAN (R 4.0.2)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.0.2)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.0.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.0.2)
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.0.2)
#>  rsample    * 0.1.0   2021-05-08 [1] CRAN (R 4.0.2)
#>  themis     * 0.1.4   2021-06-12 [1] CRAN (R 4.0.2)
#>  tibble     * 3.1.5   2021-09-30 [1] CRAN (R 4.0.2)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.0.2)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.0.2)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.0.2)
#>  yardstick  * 0.0.8   2021-03-28 [1] CRAN (R 4.0.2)
#> 
#> [1] /Library/Frameworks/R.framework/Versions/4.0/Resources/library
```
 
