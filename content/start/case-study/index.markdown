---
title: "예측 모델링 사례연구"
weight: 5
tags: [parsnip, recipes, rsample, workflows, tune]
categories: [model fitting, tuning]
description: | 
  Best Practice 를 이용하여 처음부터 끝까지 예측 모델 개발하기.
---






## 들어가기 {#intro}

[_시작하기섹션_](/start/)의 앞선 네 장에서는 모델링에 집중했었습니다. 이러한 맥락에서 모델작업할 때 필요한 tidymodles 생태계의 핵심 패키지들과 핵심 함수들을 소개했었습니다. 여기에서는 앞 장에서 배운 것 모두를 사용하여 호텔 숙박에 관한 데이터로 예측 모델을 처음부터 끝까지 만들어 볼 것입니다.


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

[Antonio, Almeida, and Nunes (2019)](https://doi.org/10.1016/j.dib.2018.11.126) 의 호텔 부킹 데이터를 사용하여, 호텔 숙박이 어린이와 아기가 포함되었는지를, 묵은 호텔, 가격 등에 관한 특징에 기반하여 예측해봅시다. 

이 데이터셋은 [`#TidyTuesday`](https://github.com/rfordatascience/tidytuesday/tree/master/data/2020/2020-02-11) 데이터셋이고 변수의 정보는 [data dictionary](https://github.com/rfordatascience/tidytuesday/tree/master/data/2020/2020-02-11#data-dictionary)에 담겨져 있습니다. 사례연구를 위해 [해당 데이터셋의 편집버전 데이터셋](https://gist.github.com/topepo/05a74916c343e57a71c51d6bc32a21ce)을 사용할 것입니다. 호텔 데이터를 R 로 불러와 봅시다. 우리 CSV 데이터가 위치한 url ("<https://tidymodels.org/start/case-study/hotels.csv>") 을 [`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html) 에 알려줍니다:


```r
library(tidymodels)
library(readr)

hotels <- 
  read_csv('https://tidymodels.org/start/case-study/hotels.csv') %>%
  mutate_if(is.character, as.factor) 

dim(hotels)
#> [1] 50000    23
```

원 논문에서 [저자들](https://doi.org/10.1016/j.dib.2018.11.126)은 많은 변수(어른/아이의 숫자, 객실 타잎, meals bought, 여행객 출신국가 등과 같은 변수)의 분포들이 취소건과 취소하지 않은 건 사이에 차이가 있습니다고 경고합니다. 이러한 정보 대부분이 여행객이 체크인 할 때 모아지고, 따라서 취소된 부킹은 취소되지 않은 부킹보다 결측 데이터가 더 많아서, 데이터가 결측되지 않았을 때 다른 특징들을 가질 것이기 때문에, 이러한 차이를 예상하는 것은 합리적입니다. 이를 감안하여 이 데이터에서 부킹취소 여행객과 하지 않은 여행객 사이에 의미있는 차이를 발견하기는 쉽지 않을 것입니다. 여기에서 모델을 만들기 위해, 우리는 데이터를 이미 필터링해서 취소하지 않은 부킹만 포함했기 때문에 _호텔숙박_ 만 분석하게 될 것입니다. 


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

우리는 숙박이 어린이나 아기를 포함했는지, 아닌지를 예측하는 모델을 만들어 볼 것입니다. 반응 변수 `children` 은 수준이 두 개인 팩터형 변수입니다:


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
[*resampling 으로 모델 평가하기*](/start/resampling/#data-split) 장에서와 같이 반응변수 `children` 이 꽤 불균형인 것을 알기 때문에, 층화 랜덤 샘플을 사용할 것입니다:  


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

여기서 `tune()` 을 이용해서 튜닝할 `penalty` 인수를 지금은 placeholder 로 설정할 것입니다. 이 인수는 우리 데이터로 예측을 하기 위한 가장 좋은 값을 찾아야 찾는 [튜닝](/start/tuning/)할 모델 하이퍼파라미터입니다. `mixture` 를 1 로 설정하는 것은 glmnet 모델이 잠재적으로 관계없는 예측을 제거하고 단순한 모델을 선택할 것이라는 것을 의미합니다. 

### 레시피 생성하기 

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

하지만, 우리는 penalty value 를 모델성능이 떨어지기 시작하는 곳 가까이 x-축을 따라 더 먼 값으로 선택하길 원할 것입니다. 예를 들어, 0.00174 penalty 값을 가진 후보 모델 12 은 수치적으로 가장 좋은 모델과 같은 성능을 가지지만 설명변수를 더 많이 제거합니다. 이 페널티 값은 위에서 실선으로 표시되었습니다. 일반적으로 덜 관련된 설명변수가 포함되지 않을 수록 좋습니다. 성능이 대략 비슷하다면 penalty 값이 큰 것을 선택하는 것이 좋습니다. 

이 값을 선택하고 validation set ROC 커브를 시각화해봅시다:

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

이 로지스틱 회귀 모델이 생성한 성능 수준은 좋지만, groundbreaking 은 아닙니다. 아마 예측 등식의 선형 속성이 이 데이터셋을 제약하고 있는 것 같습니다. 다음 단계로, tree-기반 앙상블 모델을 이용하여 생성된 highly 비선형 모델을 고려할 수 있습니다.

## 두번째 모델: tree-based ensemble {#second-model}

효과적이면서 low-maintenance 모델링 기법은 _랜덤포레스트_ 입니다. 이 모델은 [*resampling 으로 모델평가하기*](/start/resampling/) 장에서 사용되기도 했습니다. 로지스틱 회귀와 비교하여, 랜덤포레스트 모델은 더 유연합니다. 랜덤 포레스트는 일반적으로 각 수천개의 decision tree 들로 구성된 _앙상블모델_ 입니다. 각 트리는 약간 다른 버전의 트레이닝 데이터를 만나게 되고, 새로운 데이터를 예측하기 위한 splitting rule sequence 를 학습합니다. 각 tree 는 비선형이고 tree들을 aggregate 하면 랜덤 포레스트를 또한 비선형이 되지만 단일 tree 에 비해 더 robust 하고 안정성있게 됩니다. 랜덤 포레스트 같은 트리 기반 모델들은 전처리를 거의 필요로 하지 않고 다양한 종류의 설명변수들(sparse, skewed, continuous, categorical 등)을 효과적으로 다룰 수 있습니다. 

### 모델 구축과 학습 시간 개선

랜덤포레스트의 기본값 하이퍼파라미터가 꽤 괜찮은 결과를 주곤 하지만, 성능이 개선시킬 거라고 생각되는 하이퍼 파라미터 두개를 튜닝해 보려고 합니다. 안타깝게도, 랜덤 포레스트 모델을 훈련시키고 튜닝하는 것은 computationally expensive 할 수 있습니다. 모델 튜닝에 필요한 계산은 학습 시간을 개선시키기 위해 쇱게 병렬화 될 수 있습니다. tune 패키지는 [parallel processing](https://tidymodels.github.io/tune/articles/extras/optimizations.html#parallel-processing)을 대신해 줄 수 있고 사용자들이 모델을 적합할 목적으로 멀티코어나 separate machines 를 사용할 수 있게 해줍니다. 

하지만, 여기서 우리는 하나의 validation set 을 사용하고 있기 때문에, 병렬화는 tune 패키지를 사용하는 option 이 아닙니다. 우리의 케이스 스터디에서 엔진 자체가 좋은 대안을 제공합니다. ranger 패키지는 개별 랜덤 포레스트 모델을 병렬로 계산하는 빌트인 방법을 제공합니다. 이를 하기 위해, 우리가 작업해야 하는 코어 수를 알아야 합니다. parallel 패키지를 사용하여 얼마나 병렬화를 할 수 있는지 이해하기 위해 당신이 가진 컴퓨터의 코어 수를 조회할 수 있습니다:


```r
cores <- parallel::detectCores()
cores
#> [1] 8
```

우리는 8 개의 코어로 작업할 수 있습니다. parsnip `rand_forest()` 모델을 설정할 때 ranger 엔진에게 이 정보를 전달할 수 있습니다. 병렬 프로세싱을 하기 위해, `num.threads` 와 같은 엔진-specific 한 인수들을 다음과 같이 ranger 에 전달할 수 있습니다:


```r
rf_mod <- 
  rand_forest(mtry = tune(), min_n = tune(), trees = 1000) %>% 
  set_engine("ranger", num.threads = cores) %>% 
  set_mode("classification")
```

이 모델링 컨텍스트에서 잘 작동하지만, 반복하지 못합니다: 다른 resampling 방법을 사용하면, tune 이 자동으로 병렬 프로세싱을 합니다&mdash; 병렬 프로세싱을 위해 일반적으로 (여기서 우리가 했듯이) 모델링 엔진에 의존하는 것을 추천하지 않습니다.

이 모델에서, 우리는 `mtry` 와 `min_n` 인수 값들을 위한 placeholder 로 `tune()` 을 사용했습니다. 왜냐하면 이들이 우리가 [튜닝](/start/tuning/)할 하이퍼파라미터들이기 때문입니다..  

### 레시피와 워크플로 생성하기

penalized logistic regression model과 다르게 random forest model은 [더미](https://bookdown.org/max/FES/categorical-trees.html)나 정규화된 설명변수들을 필요로 하지 않습니다. 그럼에도 불구하고 `arrival_date` 변수에 다시한번 피쳐 엔지니어링을 하고 싶습니다. 전과 같이 날짜 설명변수는 랜덤 포레스트가 데이터에서 잠재된 패턴들을 너무 열심히 tease 하지 않도록 엔지니어링되었습니다.


```r
rf_recipe <- 
  recipe(children ~ ., data = hotel_other) %>% 
  step_date(arrival_date) %>% 
  step_holiday(arrival_date) %>% 
  step_rm(arrival_date) 
```

이 레시피를 우리 parsnip 모델에 추가해서 호텔숙박이 어린이나 아기들을 게스트로 포함했는지 아닌지를 랜덤포레스트로 예측하는 새로운 워크플로가 생겼습니다. 


```r
rf_workflow <- 
  workflow() %>% 
  add_model(rf_mod) %>% 
  add_recipe(rf_recipe)
```

### 모델 훈련하기와 튜닝하기

parsnip 모델을 설정할 때 우리는 튜닝할 두 개의 하이퍼파라미터를 선택했습니다:


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

`mtry` 하이퍼파라미터는 의사결정 나무의 각 노드가 만나고 학습하는 설명변수의 숫자를 설정하는데, 1에서 부터 존재하는 피쳐의 총 개수까지의 범위를 가집니다; `mtry` = 가능한 피쳐숫자 이면 모델은 배깅 decision tree 와 같습니다.  `min_n` 하이퍼파라미터는 어떤 노드에서 split 할 최소 `n` 을 설정합니다.

우리는 튜닝할 space-filling 디자인을 25 개의 후보 모델들과 사용할 것입니다: 


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

위에 출력되는 *"Creating pre-processing data to finalize unknown parameter: mtry"* 라는 메세지는 데이터셋 사이즈와 관련이 있습니다. `mtry` 는 데이터셋에서 설명변수의 개수에 의존하기 때문에, `tune_grid()` 는 `mtry` 가 데이터를 받을 때의 upper bound 를 결정합니다. 

여기에 25 개의 후보모델들 중 top 5 랜덤 포레스트 모델이 있습니다:


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

바로 이 ROC AUC 값들이 우리가 penalized 로지스틱회귀를 사용한, ROC AUC of 0.876 의 값을 얻었던 top model 보다 더 좋은 것처럼 보입니다. 

튜닝 프로세스의 결과를 플롯팅해 보면 성능을 최적화 하기 위해 `mtry` (number of predictors at each node)와 `min_n` (minimum number of data points required to keep splitting) 두개 모두 꽤 작아야 한다는 것을 강조하여 보여줍니다. 하지만, y-축 범위는 모델이 이 파라미터 값 선택에 있어 매우 로버스트하다는 것을 보여줍니다 &mdash; ROC AUC 값 중 하나를 제외한 모든 값들이 0.90 보다 큽니다. 


```r
autoplot(rf_res)
```

<img src="figs/rf-results-1.svg" width="672" />

ROC AUC 지표에 따른 가장 좋은 모델을 선택해 봅시다. 우리의 최종 튜닝 파라미터는:


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

ROC 커브를 플롯하기 위해 필요한 데이터를 계산하기 위해 `collect_predictions()`를 사용합니다. `control_grid(save_pred = TRUE)` 으로 튜닝한 다음에야 가능합니다. 출력에서 아이들을 포함하고 하지않는 호텔숙박을 예측하는 클래스 확률을 포함하는 두 개의 열을 볼 수 있습니다. 


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

우리의 가장 좋은 랜덤 포레스트 모델을 위한 예측값을 골라내기 위해, `parameters` 인수를 사용해서, `rf_best` 로 명명한 가장 좋은 하이퍼파라미터 값을 가진 우리 티블에 전달할 수 있습니다:


```r
rf_auc <- 
  rf_res %>% 
  collect_predictions(parameters = rf_best) %>% 
  roc_curve(children, .pred_children) %>% 
  mutate(model = "Random Forest")
```

이제, 우리 top penalized logistic regression model 과 랜덤포레스트 모델의 validation set ROC 커브를 비교할 수 있습니다:


```r
bind_rows(rf_auc, lr_auc) %>% 
  ggplot(aes(x = 1 - specificity, y = sensitivity, col = model)) + 
  geom_path(lwd = 1.5, alpha = 0.8) +
  geom_abline(lty = 3) + 
  coord_equal() + 
  scale_color_viridis_d(option = "plasma", end = .6)
```

<img src="figs/rf-lr-roc-curve-1.svg" width="672" />

랜덤 포레스트가 event probability thresholds 를 통틀어 유니폼하게 좋습니다.

## 마지막 적합 {#last-fit}

우리 목표는 호텔 숙박이 어린이나 아이를 포함했는지를 예측하는 것이었습니다. 랜덤 포레스트 모델은 확실히 penalized 로지스틱 회귀 모델보다 더 성능이 좋았고, 아이들에 관한 호텔숙박을 예측하는데 가장 좋은 선택이 될 수 있습니다. 가장 좋은 모델과 하이퍼파라미터를 선택한 후 마지막 단계는 테스팅으로 떼어 놓지 않은 데이터 모두(트레이닝과 밸리데이션 셋을 합침)로 최종 모델을 적합한 후 따로 떼어낸 테스트 셋으로 모델 성능을 마지막 한 번 평가하는 것입니다. 

이번에도 parsnip 객체를 처음부터 만드는 것부터 할 것입니다. 우리 랜덤 포레스트 모델로 부터 가장 좋은 하이퍼파라미터 값을 취합니다. 엔진을 설정할 때 새로운 인수를 추가합니다: `importance = "impurity"`. 이렇게 하면 이 마지막 모델의 _variable importance_ 를 얻을 수 있는데, 이는 어떤 설명변수가 모델 성능을 좌지우지하는지에 관한 직관을 제공합니다.


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

위의 적합이 된 워크플로는 테스트셋 기반 최종 지표를 포함하여 _모든것_ 을 포함합니다. 미 모델이 테스트셋에서 성능이 어떻습니까? validation set 이 미래 성능의 추정값으로서 괜찮았습니까?


```r
last_rf_fit %>% 
  collect_metrics()
#> # A tibble: 2 × 4
#>   .metric  .estimator .estimate .config             
#>   <chr>    <chr>          <dbl> <chr>               
#> 1 accuracy binary         0.946 Preprocessor1_Model1
#> 2 roc_auc  binary         0.923 Preprocessor1_Model1
```

이 ROC AUC 값은 우리가 validation set 으로 랜덤 포레스트를 튜닝했을 때 보았던 것과 꽤 가깝습니다. 우리 모델이 새로운 데이터에 어느정도의 성능을 보여줄 것인지에 관한 추정값이 보지 않은 테스트셋에서 실제로 수행한 것에서 멀리 떨어지지는 않았다는 것을 의미합니다.

이 variance importance 값들을 `.workflow` 열을 통해 접근할 수 있습니다. [pluck](https://purrr.tidyverse.org/reference/pluck.html) 을 사용하여 워크플로 열의 첫번째 요소를 추출한 후 워크플로 객체에서 [적합을 추출](https://tidymodels.github.io/workflows/reference/workflow-extractors.html) 해야 합니다. 마지막으로, vip 패키지는 top 20 피쳐에 대한 variable importance score 를 시각화합니다: 


```r
last_rf_fit %>% 
  pluck(".workflow", 1) %>%   
  pull_workflow_fit() %>% 
  vip(num_features = 20)
#> Warning: `pull_workflow_fit()` was deprecated in workflows 0.2.3.
#> Please use `extract_fit_parsnip()` instead.
```

<img src="figs/rf-importance-1.svg" width="672" />

호텔숙박에 아이들이 포함되었는지 아닌지에 관한 가장 중요한 설명변수는 객실 가격, 예약객실타잎, 최종제공된 객실타잎, 예약생성과 도착날짜 사이의 시간이었습니다.

시각화할 ROC 커브를 마지막으로 생성해 봅시다. 우리가 예측하는 사건은 `children` 팩터의 첫번째 수준 ("children") 이기 때문에, `roc_curve()` 에 [relevant class probability](https://tidymodels.github.io/yardstick/reference/roc_curve.html#relevant-level)인 `.pred_children` 을 제공합니다:


```r
last_rf_fit %>% 
  collect_predictions() %>% 
  roc_curve(children, .pred_children) %>% 
  autoplot()
```

<img src="figs/test-set-roc-curve-1.svg" width="672" />

결과에 기반한 validation set과 test set 성능 통계량은 매우 가깝기 때문에, 하이퍼파라미터 튜닝된 우리 랜덤 포레스트 모델이 새로운 데이터에 예측하는 데에 잘 작동할 것이라는 것에 꽤 높은 신뢰를 가질 수 있습니다.

## 다음단계 {#next}

[*시작하기*](/start/) 시리즈의 마지막까지 왔다면, 더 배울 준비가 되었을 것입니다! 이제 tidymodels 핵심 패키지가 어떻게 적용되는지 이해하게 되었습니다. 이 시리즈에서 소개한 기초내용에 대해 편안하게 되었다면, 모델링과 머신러닝 프로젝트에서 tidymodels 를 더 깊게 사용하는 법을 [배울](/learn/) 수 있습니다. 

다음 목적지에 관한 아이디어들입니다:

+ 종합적인 [도서](/books/)로 통계학과 모델링을 학습.

+ [package documentation sites](/packages/) 로 깊게 파서 모델링 니즈를 충적시켜주는 함수를 발견. [검색 가능한 테이블](/find/) 을 이용하여 무엇이 가능한지 탐색.

+ [tidyverse blog](https://www.tidyverse.org/tags/tidymodels/) 에서 tidymodels 패키지들에 관한 최신 소식 따라잡기.

+ [도움](/help/) 요청할 방법 찾기와 [tidymodels 에 기여](/contribute) 하여 다른사람 돕기.

### <center>Happy modeling!</center>

## Session information


```
#> ─ Session info  🧁  🧭  🎷   ───────────────────────────────────────
#>  hash: cupcake, compass, saxophone
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
#>  date     2021-12-28
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.10  2021-10-31 [1] CRAN (R 4.1.0)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  ranger       0.13.1  2021-07-14 [1] CRAN (R 4.1.0)
#>  readr      * 2.1.0   2021-11-11 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  tibble     * 3.1.6   2021-11-07 [1] CRAN (R 4.1.0)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.1.0)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.1.0)
#>  vip        * 0.3.2   2020-12-17 [1] CRAN (R 4.1.0)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.1.0)
#>  yardstick  * 0.0.9   2021-11-22 [1] CRAN (R 4.1.0)
#> 
#>  [1] /Library/Frameworks/R.framework/Versions/4.1/Resources/library
#> 
#> ────────────────────────────────────────────────────────────────────
```
