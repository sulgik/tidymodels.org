---
title: "예측 모델링 사례 연구"
weight: 5
tags: [parsnip, recipes, rsample, workflows, tune]
categories: [model fitting, tuning]
description: | 
  Best Practice 를 이용하여 처음부터 끝까지 예측 모델 개발하기.
---






## 들어가기 {#intro}

앞선 [_시작하기섹션_](/start/)의 네 장에서는 모델링에 집중했었습니다. 이러한 줄기에서 모델작업할 때 필요한 tidymodles 생태계의 핵심 패키지들과 핵심 함수들을 소개했었습니다. 여기 사례 연구에서 앞 장들에서 배운 모든 것들 사용하여 호텔 숙박에 관한 데이터로 처음부터 끝까지 예측 모델을 만들어 볼 것입니다.


<img src="img/hotel.jpg" width="90%" />


이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: glmnet, ranger, readr, tidymodels, and vip.


```r
library(tidymodels)  

# Helper packages
library(readr)       # for importing data
library(vip)         # for variable importance plots
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 호텔 부킹 데이터 {#data}

[Antonio, Almeida, and Nunes (2019)](https://doi.org/10.1016/j.dib.2018.11.126) 에 있는 호텔 부킹 데이터를 사용하여 여행객들이 어느 호텔에서 묵었는지, 가격은 얼마나였는지 등에 관한 특징들에 기반하여 어떤 호텔에서 어린이와 아기가 묵을 수 있는지를 예측해봅시다. 

이 데이터셋은 [`#TidyTuesday`](https://github.com/rfordatascience/tidytuesday/tree/master/data/2020/2020-02-11) 데이터셋이고 변수의 정보는 [data dictionary](https://github.com/rfordatascience/tidytuesday/tree/master/data/2020/2020-02-11#data-dictionary)에 담겨져 있습니다. 사례 연구를 위해 [해당 데이터셋의 편집버전 데이터셋](https://gist.github.com/topepo/05a74916c343e57a71c51d6bc32a21ce)을 사용할 것입니다. 호텔 데이터를 R 로 불러와 봅시다. 우리 CSV 데이터가 위치한 url ("<https://tidymodels.org/start/case-study/hotels.csv>") 을 [`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html) 에 알려줍니다:


```r
library(tidymodels)
library(readr)

hotels <- 
  read_csv('https://tidymodels.org/start/case-study/hotels.csv') %>%
  mutate_if(is.character, as.factor) 

dim(hotels)
#> [1] 50000    23
```

원 논문에서 [저자들](https://doi.org/10.1016/j.dib.2018.11.126)은 많은 변수(such as number of adults/children, room type, meals bought, country of origin of the guests, and so forth)의 분포들이 취소건과 취소하지 않은 건 사이에 차이가 있습니다고 경고합니다. 이러한 정보 대부분이 숙박객이 체크인 할 때 모아지고, 따라서 취소된 부킹은 취소되지 않은 부킹보다 결측 데이터가 더 많아서, 데이터가 결측되지 않았을 때 다른 특징들을 가질 것이기 때문에, 이러한 차이를 예상하는 것은 합리적입니다. 이를 감안하여 이 데이터에서 부킹을 캔슬한 손님과 하지 않은 손님 사이에 의미있는 차이를 발견하기 쉽지 않을 것입니다. 여기에서 모델을 만들기 위해, 우리는 데이터를 이미 필터링해서 취소하지 않은 부킹만 포함했기 때문에 _호텔숙박_ 만 분석하게 될 것입니다. 


```r
glimpse(hotels)
#> Rows: 50,000
#> Columns: 23
#> $ hotel                          <fct> City_Hotel, City_Hotel, Resort_Hotel, R…
#> $ lead_time                      <dbl> 217, 2, 95, 143, 136, 67, 47, 56, 80, 6…
#> $ stays_in_weekend_nights        <dbl> 1, 0, 2, 2, 1, 2, 0, 0, 0, 2, 1, 0, 1, …
#> $ stays_in_week_nights           <dbl> 3, 1, 5, 6, 4, 2, 2, 3, 4, 2, 2, 1, 2, …
#> $ adults                         <dbl> 2, 2, 2, 2, 2, 2, 2, 0, 2, 2, 2, 1, 2, …
#> $ children                       <fct> none, none, none, none, none, none, chi…
#> $ meal                           <fct> BB, BB, BB, HB, HB, SC, BB, BB, BB, BB,…
#> $ country                        <fct> DEU, PRT, GBR, ROU, PRT, GBR, ESP, ESP,…
#> $ market_segment                 <fct> Offline_TA/TO, Direct, Online_TA, Onlin…
#> $ distribution_channel           <fct> TA/TO, Direct, TA/TO, TA/TO, Direct, TA…
#> $ is_repeated_guest              <dbl> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, …
#> $ previous_cancellations         <dbl> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, …
#> $ previous_bookings_not_canceled <dbl> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, …
#> $ reserved_room_type             <fct> A, D, A, A, F, A, C, B, D, A, A, D, A, …
#> $ assigned_room_type             <fct> A, K, A, A, F, A, C, A, D, A, D, D, A, …
#> $ booking_changes                <dbl> 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, …
#> $ deposit_type                   <fct> No_Deposit, No_Deposit, No_Deposit, No_…
#> $ days_in_waiting_list           <dbl> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, …
#> $ customer_type                  <fct> Transient-Party, Transient, Transient, …
#> $ average_daily_rate             <dbl> 80.75, 170.00, 8.00, 81.00, 157.60, 49.…
#> $ required_car_parking_spaces    <fct> none, none, none, none, none, none, non…
#> $ total_of_special_requests      <dbl> 1, 3, 2, 1, 4, 1, 1, 1, 1, 1, 0, 1, 0, …
#> $ arrival_date                   <date> 2016-09-01, 2017-08-25, 2016-11-19, 20…
```

우리는 실제 숙박이 어린이들이나 아기를 포함했는지, 아닌지를 예측하는 모델을 만들어 볼 것입니다. 반응 변수 `children` 은 수준이 두개인 팩터형 변수입니다:


```r
hotels %>% 
  count(children) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   children     n   prop
#>   <fct>    <int>  <dbl>
#> 1 children  4038 0.0808
#> 2 none     45962 0.919
```

아이들은 예약 수 중 단지 8.1% 에만 있는 것을 알 수 있습니다. 이러한 클래스 불균형은 분석을 좌지우지 할 수 있습니다. [recipes](/find/recipes/) 를 사용하거나 [themis](https://tidymodels.github.io/themis/)와 같은 더 전문화된 패키지를 사용하여 이러한 이슈와 싸울 수 있지만, 아래에 나와있는 방법들은 데이터를 있는 그대로 분석합니다.

## 데이터 쪼개기와 리샘플링 {#data-split}

데이터 쪼개기 전략으로 숙박데이터의 25% 를 테스트셋으로 따로 떼어 봅시다. 
of the stays to the test set. As in our [*resampling 으로 모델 평가하기*](/start/resampling/#data-split) 장에서와 같이 반응변수 `children` 이 꽤 불균형인것을 알기 때문에, 층화 랜덤 샘플을 사용할 것입니다:  


```r
set.seed(123)
splits      <- initial_split(hotels, strata = children)

hotel_other <- training(splits)
hotel_test  <- testing(splits)

# training set proportions by children
hotel_other %>% 
  count(children) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   children     n   prop
#>   <fct>    <int>  <dbl>
#> 1 children  3027 0.0807
#> 2 none     34473 0.919

# test set proportions by children
hotel_test  %>% 
  count(children) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   children     n   prop
#>   <fct>    <int>  <dbl>
#> 1 children  1011 0.0809
#> 2 none     11489 0.919
```

지금까지 우리는 주요 리샘플링 방법으로 [`rsample::vfold_cv()`](https://tidymodels.github.io/rsample/reference/vfold_cv.html) 을 사용한 10-fold cross-validation 을 사용했습니다. 이 방법은 트레이닝셋 ( _분석_ 과 _평가_ 셋으로 더 쪼갬) 10 개의 다른 리샘플들을 생성하고 10 개의 다른 성능지표들을 생성한 뒤 취합한다.

이번 케이스 스터디에 대해, 여러번 리샘플링 하는 것 대신, _validation set_ 이라고 부르는 리샘플 하나만 생성해봅시다. tidymodels 에서 validation set 은 리샘플링 일반복으로 취급됩니다. `hotel_other` 라고 부르는 테스팅 사용되지 않은 37,500 개의 숙박으로 부터 split 이 될 것입니다. 이 split 은 두 개의 새로운 데이터셋을 생성합니다:

+ _validation set_ 이라고 부르는, 성능측정 목적으로 따로 떼어낸 셋

+ _training set_ 이라고 부르는, 모델 적합하는데 사용하는 남은 데이터셋. 

<img src="img/validation-split.svg" width="50%" style="display: block; margin: auto;" />

`validation_split()` 함수를 사용하여 20% of the `hotel_other` 숙박의 20% 를  _validation set_ 에 30,000 숙박은 _training set_ 에 할당할 것입니다. 이는 우리 모델 성능 지표가 7,500 개의 호텔 숙박 데이터셋으로 계산된다는 것을 의미합니다. 이는 꽤 큰 규모여서, 이러한 데이터 양은 각 모델이 리샘플링 일반복으로 얼마나 잘 예측하는지에 대한 믿을만한 지표가 되기 충분한 precision 을 제공할 것입니다.


```r
set.seed(234)
val_set <- validation_split(hotel_other, 
                            strata = children, 
                            prop = 0.80)
val_set
#> # Validation Set Split (0.8/0.2)  using stratification 
#> # A tibble: 1 × 2
#>   splits               id        
#>   <list>               <chr>     
#> 1 <split [30000/7500]> validation
```

이 함수는 `initial_split()` 과 같이 `strata` 인수를 갖는데, 층화 샘플링을 사용하여 리샘플을 생성합니다. 이는 새로운 validation 과 training set 이 아이들이 있고 없는 숙박의 비율이 원 `hotel_other` 비율과 비교하여 대략 같은 비율이 될 것이라는 점을 의미합니다.

## 첫 모델: penalized logistic regression {#first-model}

우리의 반응변수 `children` 은 범주형이기 때문에, 로지스틱 회귀가 시작하기 좋은 첫번째 모델이 됩니다. 트레이닝 동안 feature selection 을 수행할 모델을 사용해봅시다. [glmnet](https://cran.r-project.org/web/packages/glmnet/index.html) R 패키지는 penalized maximum likelihood 를 통해 일반화 선형 모형을 적합합니다. 로지스틱 회귀 기울기 파라미터 추정방법은 _penalty_ 를 프로세스에 사용해서 덜 관련된 설명변수들을 0 값으로 보냅니다. glmnet penalization 방법들 중 하나인, [lasso method](https://en.wikipedia.org/wiki/Lasso_(statistics)) 은 충분히 큰 penalty 가 사용되면 설명변수 기울기를 실제 0 으로 설정할 수 있습니다. 

### 모델 만들기

feature selection penalty 를 사용하는 penalized 로지스틱 회구 모델을 specify 하기 위해 parsnip 패키지를 [glmnet engine](/find/parsnip/) 과 사용해 봅시다:  


```r
lr_mod <- 
  logistic_reg(penalty = tune(), mixture = 1) %>% 
  set_engine("glmnet")
```

We'll set the `penalty` argument to `tune()` as a placeholder for now. This is a model hyperparameter that we will [tune](/start/tuning/) to find the best value for making predictions with our data. Setting `mixture` to a value of one means that the glmnet model will potentially remove irrelevant predictors and choose a simpler model. 

### Create the recipe 

[recipe](/start/recipes/) 를 생성하여 이 모델을 위해 호텔숙박 데이터를 준비하는 전처리 과정을 정의해 봅시다. 도착 날짜에 관련된 중요한 구성요소들을 반영하는 데이터 기반 설명변수 셋을 생성하는 것이 의미가 있을 수 있습니다. 우리는 이미 앞에서 [여러 recipe step](/start/recipes/#features)을 소개하여 날짜로 부터 피쳐들을 생성해보았습니다:

+ `step_date()` 은 연도, 월, 요일 설명변수를 생성.

+ `step_holiday()` 은 특별한 holiday 를 가리키는 변수 집합을 생성. 이 호텔이 어디에 위치해 있는지 알지 못해도, 대부분 숙박의 origin 을 위한 국가들이 유럽에 기반하고 있다는 것은 알고 있습니다.

+ `step_rm()` 은 변수들을 제거; 여기서 우리는 원 날짜 변수를 모델에서 더 이상 사용하지 않아서, 이를 제거하기 위해 사용할 것이다.

추가적으로 모든 범주형 설명변수 (예, `distribution_channel`, `hotel`, ...) 들은 더미 변수들로 바뀔 것이고, 모든 수치형 변수들은 centered 되고 scaled 될 것이다.

+ `step_dummy()` 는 문자와 팩터형 (즉, 명목형 변수들) 을 원 데이터의 수준들을 위한 하나 이상의 수치형 binary model terms 으로 변환.

+ `step_zv()` 은 하나의 유일한 값을 하나만 포함(예, 모두 0)하는 indicator 변수들을 제거. penalized models 에서 설명변수는 center 되고 scale 되어야 하기 때문에 이 스텝은 중요합니다.

+ `step_normalize()` 는 수치형 변수들을 centering 하고 scaling 함.

이 모든 스텝의 penalized logistic regression 모델의 레시피로 묶으면: 


```r
holidays <- c("AllSouls", "AshWednesday", "ChristmasEve", "Easter", 
              "ChristmasDay", "GoodFriday", "NewYearsDay", "PalmSunday")

lr_recipe <- 
  recipe(children ~ ., data = hotel_other) %>% 
  step_date(arrival_date) %>% 
  step_holiday(arrival_date, holidays = holidays) %>% 
  step_rm(arrival_date) %>% 
  step_dummy(all_nominal(), -all_outcomes()) %>% 
  step_zv(all_predictors()) %>% 
  step_normalize(all_predictors())
```


### 워크플로 생성

[*레시피로 전처리하기*](/start/recipes/#fit-workflow)에서와 같이, 모델와 레시피를 하나의 `workflow()` 객체로 번들하여 R 객체 관리를 더 쉽게 해 봅시다:


```r
lr_workflow <- 
  workflow() %>% 
  add_model(lr_mod) %>% 
  add_recipe(lr_recipe)
```

### 튜닝을 위한 그리드 생성

이 모델을 적합하기 전에, 튜닝할 `penalty` 값의 그리드를 설정해야 합니다. [*모델 파라미터 튜닝하기*](/start/tuning/) 장에서 [`dials::grid_regular()`](start/tuning/#tune-grid)을 사용하여 하이퍼파라미터 두개의 조합에 기반하여 expanded 그리드를 생성하였습니다. 여기서 튜닝할 하이퍼파라미터가 하나이므로, 30개 후보 값들을 가진 하나의 열 티블을 수동으로 이용하여 그리드를 설정할 수 있습니다.


```r
lr_reg_grid <- tibble(penalty = 10^seq(-4, -1, length.out = 30))

lr_reg_grid %>% top_n(-5) # lowest penalty values
#> Selecting by penalty
#> # A tibble: 5 × 1
#>    penalty
#>      <dbl>
#> 1 0.0001  
#> 2 0.000127
#> 3 0.000161
#> 4 0.000204
#> 5 0.000259
lr_reg_grid %>% top_n(5)  # highest penalty values
#> Selecting by penalty
#> # A tibble: 5 × 1
#>   penalty
#>     <dbl>
#> 1  0.0386
#> 2  0.0489
#> 3  0.0621
#> 4  0.0788
#> 5  0.1
```

### 모델 훈련과 튜닝하기

`tune::tune_grid()` 를 사용하여 이 30 개의 penalized logistic regression models 을 훈련시켜 봅시다. validation set 예측값을 저장할 수 있는데 (`control_grid()` 호출 사용) 이렇게 하면, 진단정보가 모델 적합 이후 사용할 수 있습니다. 이벤트 threshold 의 continum 을 통튼 모델 성능을 정량화하는데 Area under ROC 커브를 사용할 것입니다 (event rate&mdash;아이들을 포함한 숙박비율&mdash 이 데이터에서 매우 낮음을 기억하세요).


```r
lr_res <- 
  lr_workflow %>% 
  tune_grid(val_set,
            grid = lr_reg_grid,
            control = control_grid(save_pred = TRUE),
            metrics = metric_set(roc_auc))
```

area under the ROC 커브를 penalty 값들 범위에 상대하여 plotting 하면 validation set 지표들을 시각화 하는 것이 더 쉬울 것입니다:


```r
lr_plot <- 
  lr_res %>% 
  collect_metrics() %>% 
  ggplot(aes(x = penalty, y = mean)) + 
  geom_point() + 
  geom_line() + 
  ylab("Area under the ROC Curve") +
  scale_x_log10(labels = scales::label_number())

lr_plot 
```

<img src="figs/logistic-results-1.svg" width="576" />

이 플롯은 모델 성능이 더 작은 penalty 값들에서 일반적으로 더 좋다는 것을 보여줍니다. 이는 설명변수 대부분이 모델에 중요하다는 것을 제안합니다. ROC 커브가 높은 penalty 값에서 가파르게 떨어지는 것을 볼 수도 있습니다. 충분히 큰 penalty 는 모델에서 _모든_ 설명변수들을 제거할 것이기 때문에 발생합니다. 예측정확도가 설명변수가 없는 모델에서 급감하는 것은 놀라운 일이 아닙니다 (0.50 ROC AUC 값은 모델이 맞는 클래스를 예측할 때 우연히 하는 것과 성능이 같다는 것을 의미한다는 것을 기억하세요).

우리 모델 성능은 더 작은 페널티 값에서 평평한 것 처럼 보입니다. 따라서 `roc_auc` 하나만 사용하면 하이퍼파라미터의 "가장좋은" 값에 여러 옵션들이 있다고 결론내리게 됩니다: 


```r
top_models <-
  lr_res %>% 
  show_best("roc_auc", n = 15) %>% 
  arrange(penalty) 
top_models
#> # A tibble: 15 × 7
#>     penalty .metric .estimator  mean     n std_err .config              
#>       <dbl> <chr>   <chr>      <dbl> <int>   <dbl> <chr>                
#>  1 0.000127 roc_auc binary     0.872     1      NA Preprocessor1_Model02
#>  2 0.000161 roc_auc binary     0.872     1      NA Preprocessor1_Model03
#>  3 0.000204 roc_auc binary     0.873     1      NA Preprocessor1_Model04
#>  4 0.000259 roc_auc binary     0.873     1      NA Preprocessor1_Model05
#>  5 0.000329 roc_auc binary     0.874     1      NA Preprocessor1_Model06
#>  6 0.000418 roc_auc binary     0.874     1      NA Preprocessor1_Model07
#>  7 0.000530 roc_auc binary     0.875     1      NA Preprocessor1_Model08
#>  8 0.000672 roc_auc binary     0.875     1      NA Preprocessor1_Model09
#>  9 0.000853 roc_auc binary     0.876     1      NA Preprocessor1_Model10
#> 10 0.00108  roc_auc binary     0.876     1      NA Preprocessor1_Model11
#> 11 0.00137  roc_auc binary     0.876     1      NA Preprocessor1_Model12
#> 12 0.00174  roc_auc binary     0.876     1      NA Preprocessor1_Model13
#> 13 0.00221  roc_auc binary     0.876     1      NA Preprocessor1_Model14
#> 14 0.00281  roc_auc binary     0.875     1      NA Preprocessor1_Model15
#> 15 0.00356  roc_auc binary     0.873     1      NA Preprocessor1_Model16
```



이 티블의 모든 후보모델은 아래 행의 모델보다 더 많은 설명변수를 가집니다. `select_best()` 를 하면 점선보다 낮은 값에 보이는 0.00137 페널티 값을 가진 후보 모델 11 를 반환할 것입니다.

<img src="figs/lr-plot-lines-1.svg" width="576" />

However, we may want to choose a penalty value further along the x-axis, closer to where we start to see the decline in model performance. For example, candidate model 12 with a penalty value of 0.00174 has effectively the same performance as the numerically best model, but might eliminate more predictors. This penalty value is marked by the solid line above. In general, fewer irrelevant predictors is better. If performance is about the same, we'd prefer to choose a higher penalty value. 

Let's select this value and visualize the validation set ROC curve:

```r
lr_best <- 
  lr_res %>% 
  collect_metrics() %>% 
  arrange(penalty) %>% 
  slice(12)
lr_best
#> # A tibble: 1 × 7
#>   penalty .metric .estimator  mean     n std_err .config              
#>     <dbl> <chr>   <chr>      <dbl> <int>   <dbl> <chr>                
#> 1 0.00137 roc_auc binary     0.876     1      NA Preprocessor1_Model12
```



```r
lr_auc <- 
  lr_res %>% 
  collect_predictions(parameters = lr_best) %>% 
  roc_curve(children, .pred_children) %>% 
  mutate(model = "Logistic Regression")

autoplot(lr_auc)
```

<img src="figs/logistic-roc-curve-1.svg" width="672" />

The level of performance generated by this logistic regression model is good, but not groundbreaking. Perhaps the linear nature of the prediction equation is too limiting for this data set. As a next step, we might consider a highly non-linear model generated using a tree-based ensemble method. 

## 두번째 모델: tree-based ensemble {#second-model}

An effective and low-maintenance modeling technique is a _random forest_. This model was also used in our [*Evaluate your model with resampling*](/start/resampling/) article. Compared to logistic regression, a random forest model is more flexible. A random forest is an _ensemble model_ typically made up of thousands of decision trees, where each individual tree sees a slightly different version of the training data and learns a sequence of splitting rules to predict new data. Each tree is non-linear, and aggregating across trees makes random forests also non-linear but more robust and stable compared to individual trees. Tree-based models like random forests require very little preprocessing and can effectively handle many types of predictors (sparse, skewed, continuous, categorical, etc.).

### Build the model and improve training time

Although the default hyperparameters for random forests tend to give reasonable results, we'll plan to tune two hyperparameters that we think could improve performance. Unfortunately, random forest models can be computationally expensive to train and to tune. The computations required for model tuning can usually be easily parallelized to improve training time. The tune package can do [parallel processing](https://tidymodels.github.io/tune/articles/extras/optimizations.html#parallel-processing) for you, and allows users to use multiple cores or separate machines to fit models. 

But, here we are using a single validation set, so parallelization isn't an option using the tune package. For this specific case study, a good alternative is provided by the engine itself. The ranger package offers a built-in way to compute individual random forest models in parallel. To do this, we need to know the the number of cores we have to work with. We can use the parallel package to query the number of cores on your own computer to understand how much parallelization you can do: 


```r
cores <- parallel::detectCores()
cores
#> [1] 4
```

We have 4 cores to work with. We can pass this information to the ranger engine when we set up our parsnip `rand_forest()` model. To enable parallel processing, we can pass engine-specific arguments like `num.threads` to ranger when we set the engine: 


```r
rf_mod <- 
  rand_forest(mtry = tune(), min_n = tune(), trees = 1000) %>% 
  set_engine("ranger", num.threads = cores) %>% 
  set_mode("classification")
```

This works well in this modeling context, but it bears repeating: if you use any other resampling method, let tune do the parallel processing for you &mdash; we typically do not recommend relying on the modeling engine (like we did here) to do this.

In this model, we used `tune()` as a placeholder for the `mtry` and `min_n` argument values, because these are our two hyperparameters that we will [tune](/start/tuning/).  

### Create the recipe and workflow

Unlike penalized logistic regression models, random forest models do not require [dummy](https://bookdown.org/max/FES/categorical-trees.html) or normalized predictor variables. Nevertheless, we want to do some feature engineering again with our `arrival_date` variable. As before, the date predictor is engineered so that the random forest model does not need to work hard to tease these potential patterns from the data.  


```r
rf_recipe <- 
  recipe(children ~ ., data = hotel_other) %>% 
  step_date(arrival_date) %>% 
  step_holiday(arrival_date) %>% 
  step_rm(arrival_date) 
```

Adding this recipe to our parsnip model gives us a new workflow for predicting whether a hotel stay included children and/or babies as guests with a random forest:


```r
rf_workflow <- 
  workflow() %>% 
  add_model(rf_mod) %>% 
  add_recipe(rf_recipe)
```

### Train and tune the model

When we set up our parsnip model, we chose two hyperparameters for tuning:


```r
rf_mod
#> Random Forest Model Specification (classification)
#> 
#> Main Arguments:
#>   mtry = tune()
#>   trees = 1000
#>   min_n = tune()
#> 
#> Engine-Specific Arguments:
#>   num.threads = cores
#> 
#> Computational engine: ranger

# show what will be tuned
rf_mod %>%    
  parameters()  
#> Collection of 2 parameters for tuning
#> 
#>  identifier  type    object
#>        mtry  mtry nparam[?]
#>       min_n min_n nparam[+]
#> 
#> Model parameters needing finalization:
#>    # Randomly Selected Predictors ('mtry')
#> 
#> See `?dials::finalize` or `?dials::update.parameters` for more information.
```

The `mtry` hyperparameter sets the number of predictor variables that each node in the decision tree "sees" and can learn about, so it can range from 1 to the total number of features present; when `mtry` = all possible features, the model is the same as bagging decision trees. The `min_n` hyperparameter sets the minimum `n` to split at any node.

We will use a space-filling design to tune, with 25 candidate models: 


```r
set.seed(345)
rf_res <- 
  rf_workflow %>% 
  tune_grid(val_set,
            grid = 25,
            control = control_grid(save_pred = TRUE),
            metrics = metric_set(roc_auc))
#> i Creating pre-processing data to finalize unknown parameter: mtry
```

The message printed above *"Creating pre-processing data to finalize unknown parameter: mtry"* is related to the size of the data set. Since `mtry` depends on the number of predictors in the data set, `tune_grid()` determines the upper bound for `mtry` once it receives the data. 

Here are our top 5 random forest models, out of the 25 candidates:


```r
rf_res %>% 
  show_best(metric = "roc_auc")
#> # A tibble: 5 × 8
#>    mtry min_n .metric .estimator  mean     n std_err .config              
#>   <int> <int> <chr>   <chr>      <dbl> <int>   <dbl> <chr>                
#> 1     8     7 roc_auc binary     0.926     1      NA Preprocessor1_Model13
#> 2    12     7 roc_auc binary     0.926     1      NA Preprocessor1_Model01
#> 3    13     4 roc_auc binary     0.925     1      NA Preprocessor1_Model05
#> 4     9    12 roc_auc binary     0.924     1      NA Preprocessor1_Model19
#> 5     6    18 roc_auc binary     0.924     1      NA Preprocessor1_Model24
```

Right away, we see that these values for area under the ROC look more promising than our top model using penalized logistic regression, which yielded an ROC AUC of 0.876.

Plotting the results of the tuning process highlights that both `mtry` (number of predictors at each node) and `min_n` (minimum number of data points required to keep splitting) should be fairly small to optimize performance. However, the range of the y-axis indicates that the model is very robust to the choice of these parameter values &mdash; all but one of the ROC AUC values are greater than 0.90.


```r
autoplot(rf_res)
```

<img src="figs/rf-results-1.svg" width="672" />

Let's select the best model according to the ROC AUC metric. Our final tuning parameter values are:


```r
rf_best <- 
  rf_res %>% 
  select_best(metric = "roc_auc")
rf_best
#> # A tibble: 1 × 3
#>    mtry min_n .config              
#>   <int> <int> <chr>                
#> 1     8     7 Preprocessor1_Model13
```

To calculate the data needed to plot the ROC curve, we use `collect_predictions()`. This is only possible after tuning with `control_grid(save_pred = TRUE)`. In the output, you can see the two columns that hold our class probabilities for predicting hotel stays including and not including children.


```r
rf_res %>% 
  collect_predictions()
#> # A tibble: 187,500 × 8
#>   id         .pred_children .pred_none  .row  mtry min_n children .config       
#>   <chr>               <dbl>      <dbl> <int> <int> <int> <fct>    <chr>         
#> 1 validation         0.152       0.848    13    12     7 none     Preprocessor1…
#> 2 validation         0.0302      0.970    20    12     7 none     Preprocessor1…
#> 3 validation         0.513       0.487    22    12     7 children Preprocessor1…
#> 4 validation         0.0103      0.990    23    12     7 none     Preprocessor1…
#> 5 validation         0.0111      0.989    31    12     7 none     Preprocessor1…
#> # … with 187,495 more rows
```

To filter the predictions for only our best random forest model, we can use the `parameters` argument and pass it our tibble with the best hyperparameter values from tuning, which we called `rf_best`:


```r
rf_auc <- 
  rf_res %>% 
  collect_predictions(parameters = rf_best) %>% 
  roc_curve(children, .pred_children) %>% 
  mutate(model = "Random Forest")
```

Now, we can compare the validation set ROC curves for our top penalized logistic regression model and random forest model: 


```r
bind_rows(rf_auc, lr_auc) %>% 
  ggplot(aes(x = 1 - specificity, y = sensitivity, col = model)) + 
  geom_path(lwd = 1.5, alpha = 0.8) +
  geom_abline(lty = 3) + 
  coord_equal() + 
  scale_color_viridis_d(option = "plasma", end = .6)
```

<img src="figs/rf-lr-roc-curve-1.svg" width="672" />

The random forest is uniformly better across event probability thresholds. 

## 마지막 적합 {#last-fit}

Our goal was to predict which hotel stays included children and/or babies. The random forest model clearly performed better than the penalized logistic regression model, and would be our best bet for predicting hotel stays with and without children. After selecting our best model and hyperparameter values, our last step is to fit the final model on all the rows of data not originally held out for testing (both the training and the validation sets combined), and then evaluate the model performance one last time with the held-out test set. 

We'll start by building our parsnip model object again from scratch. We take our best hyperparameter values from our random forest model. When we set the engine, we add a new argument: `importance = "impurity"`. This will provide _variable importance_ scores for this last model, which gives some insight into which predictors drive model performance.


```r
# the last model
last_rf_mod <- 
  rand_forest(mtry = 8, min_n = 7, trees = 1000) %>% 
  set_engine("ranger", num.threads = cores, importance = "impurity") %>% 
  set_mode("classification")

# the last workflow
last_rf_workflow <- 
  rf_workflow %>% 
  update_model(last_rf_mod)

# the last fit
set.seed(345)
last_rf_fit <- 
  last_rf_workflow %>% 
  last_fit(splits)

last_rf_fit
#> # Resampling results
#> # Manual resampling 
#> # A tibble: 1 × 6
#>   splits                id               .metrics  .notes .predictions .workflow
#>   <list>                <chr>            <list>    <list> <list>       <list>   
#> 1 <split [37500/12500]> train/test split <tibble … <tibb… <tibble [12… <workflo…
```

This fitted workflow contains _everything_, including our final metrics based on the test set. So, how did this model do on the test set? Was the validation set a good estimate of future performance? 


```r
last_rf_fit %>% 
  collect_metrics()
#> # A tibble: 2 × 4
#>   .metric  .estimator .estimate .config             
#>   <chr>    <chr>          <dbl> <chr>               
#> 1 accuracy binary         0.946 Preprocessor1_Model1
#> 2 roc_auc  binary         0.923 Preprocessor1_Model1
```

This ROC AUC value is pretty close to what we saw when we tuned the random forest model with the validation set, which is good news. That means that our estimate of how well our model would perform with new data was not too far off from how well our model actually performed with the unseen test data.

We can access those variable importance scores via the `.workflow` column. We first need to [pluck](https://purrr.tidyverse.org/reference/pluck.html) out the first element in the workflow column, then [pull out the fit](https://tidymodels.github.io/workflows/reference/workflow-extractors.html) from the workflow object. Finally, the vip package helps us visualize the variable importance scores for the top 20 features: 


```r
last_rf_fit %>% 
  pluck(".workflow", 1) %>%   
  pull_workflow_fit() %>% 
  vip(num_features = 20)
#> Warning: `pull_workflow_fit()` was deprecated in workflows 0.2.3.
#> Please use `extract_fit_parsnip()` instead.
```

<img src="figs/rf-importance-1.svg" width="672" />

The most important predictors in whether a hotel stay had children or not were the daily cost for the room, the type of room reserved, the type of room that was ultimately assigned, and the time between the creation of the reservation and the arrival date. 

Let's generate our last ROC curve to visualize. Since the event we are predicting is the first level in the `children` factor ("children"), we provide `roc_curve()` with the [relevant class probability](https://tidymodels.github.io/yardstick/reference/roc_curve.html#relevant-level) `.pred_children`:


```r
last_rf_fit %>% 
  collect_predictions() %>% 
  roc_curve(children, .pred_children) %>% 
  autoplot()
```

<img src="figs/test-set-roc-curve-1.svg" width="672" />

Based on these results, the validation set and test set performance statistics are very close, so we would have pretty high confidence that our random forest model with the selected hyperparameters would perform well when predicting new data.

## 다음단계 {#next}

If you've made it to the end of this series of [*Get Started*](/start/) articles, we hope you feel ready to learn more! You now know the core tidymodels packages and how they fit together. After you are comfortable with the basics we introduced in this series, you can [learn how to go farther](/learn/) with tidymodels in your modeling and machine learning projects. 

Here are some more ideas for where to go next:

+ Study up on statistics and modeling with our comprehensive [books](/books/).

+ Dig deeper into the [package documentation sites](/packages/) to find functions that meet your modeling needs. Use the [searchable tables](/find/) to explore what is possible.

+ Keep up with the latest about tidymodels packages at the [tidyverse blog](https://www.tidyverse.org/tags/tidymodels/).

+ Find ways to ask for [help](/help/) and [contribute to tidymodels](/contribute) to help others.

### <center>Happy modeling!</center>

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
#>  date     2021-12-26                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package    * version date       lib source        
#>  broom      * 0.7.9   2021-07-27 [1] CRAN (R 4.0.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.0.2)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.0.2)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.0.2)
#>  glmnet     * 4.0     2020-05-14 [1] CRAN (R 4.0.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.0.2)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.0.2)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.0.0)
#>  ranger     * 0.13.1  2021-07-14 [1] CRAN (R 4.0.2)
#>  readr      * 1.4.0   2020-10-05 [1] CRAN (R 4.0.2)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.0.2)
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.0.2)
#>  rsample    * 0.1.0   2021-05-08 [1] CRAN (R 4.0.2)
#>  tibble     * 3.1.5   2021-09-30 [1] CRAN (R 4.0.2)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.0.2)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.0.2)
#>  vip        * 0.3.2   2020-12-17 [1] CRAN (R 4.0.2)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.0.2)
#>  yardstick  * 0.0.8   2021-03-28 [1] CRAN (R 4.0.2)
#> 
#> [1] /Library/Frameworks/R.framework/Versions/4.0/Resources/library
```
