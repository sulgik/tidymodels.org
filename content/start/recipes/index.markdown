---
title: "레시피로 데이터 전처리하기"
weight: 2
tags: [recipes, parsnip, workflows, yardstick, broom]
categories: [pre-processing]
description: | 
  Prepare data for modeling with modular preprocessing steps.
---
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />





## 들어가기 {#intro}

[*모델 만들기*](/start/models/) 장에서는 [parsnip 패키지](https://parsnip.tidymodels.org/) 를 사용하여 엔진을 바꿔가며 모델을 정의하고 훈련시키는 법에 대해 배웠습니다. 이 챕터에서 살펴볼 tidymodels 의 또 다른 패키지인 [recipes](https://recipes.tidymodels.org/) 는, 트레이닝 *전*에 데이터를 전처리를 도와주기 위해 설계되었습니다. 레시피(recipe)는 다음과 같이 일련의 전처리 과정들로 구성됩니다:

+ 정성 설명변수를 indicator 변수 (더미 변수로도 알려짐) 로 변환,

+ 데이터를 다른 스케일로 변환 (예, 변수에 로그를 취함),

+ 설명변수들의 그룹을 모두 변환,

+ 원변수로부터 핵심변수를 추출 (예, 날짜에서 요일을 추출),

등입니다. 
R 의 공식(formula) 인터페이스에 익숙하다면, 이러한 것들 대부분이 친숙할 것이고 공식이 이미 수행 중이라는 것을 알 것입니다. 
레시피는 이러한 것들 대부분을 수행하는데 사용할 수 있지만, 더 확장된 범위의 것들을 할 수 있습니다. 
이번 장에서는 레시피를 사용하여 모델링하는 법을 알아볼 것입니다.

이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: nycflights13, skimr, and tidymodels.


```r
library(tidymodels)      # for the recipes package, along with the rest of tidymodels

# Helper packages
library(nycflights13)    # for flight data
library(skimr)           # for variable summaries
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 뉴욕시 항공기 데이터 {#data}




[nycflights13 데이터](https://github.com/hadley/nycflights13)에서 여객기가 30 분 이상 연착될지를 예측해봅시다. 이 데이터에는 뉴욕시 인근에서 출발한 항공편 325,819 편에 대한 정보가 있습니다. 
우선 데이터를 로드하고 변수에 수정을 몇 개 합시다.

이 데이터셋의 16% 에 해당하는 항공편이 30 분보다 더 늦게 도착했다는 것을 볼 수 있습니다.


```r
flight_data %>% 
  count(arr_delay) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   arr_delay      n  prop
#>   <fct>      <int> <dbl>
#> 1 late       52540 0.161
#> 2 on_time   273279 0.839
```

레시피를 작성하기 전에 전처리와 모델링에 중요한 변수들을 빠르게 살펴봅시다.

첫번째로, 우리가 생성한 `arr_delay` 변수가 팩터형 변수임을 주목하세요; 훈련시킬 로지스틱 회귀 모형의 출력 변수가 팩터형이라는 것이 중요합니다.


```r
glimpse(flight_data)
#> Rows: 325,819
#> Columns: 10
#> $ dep_time  <int> 517, 533, 542, 544, 554, 554, 555, 557, 557, 558, 558, 558, …
#> $ flight    <int> 1545, 1714, 1141, 725, 461, 1696, 507, 5708, 79, 301, 49, 71…
#> $ origin    <fct> EWR, LGA, JFK, JFK, LGA, EWR, EWR, LGA, JFK, LGA, JFK, JFK, …
#> $ dest      <fct> IAH, IAH, MIA, BQN, ATL, ORD, FLL, IAD, MCO, ORD, PBI, TPA, …
#> $ air_time  <dbl> 227, 227, 160, 183, 116, 150, 158, 53, 140, 138, 149, 158, 3…
#> $ distance  <dbl> 1400, 1416, 1089, 1576, 762, 719, 1065, 229, 944, 733, 1028,…
#> $ carrier   <fct> UA, UA, AA, B6, DL, UA, B6, EV, B6, AA, B6, B6, UA, UA, AA, …
#> $ date      <date> 2013-01-01, 2013-01-01, 2013-01-01, 2013-01-01, 2013-01-01,…
#> $ arr_delay <fct> on_time, on_time, late, on_time, on_time, on_time, on_time, …
#> $ time_hour <dttm> 2013-01-01 05:00:00, 2013-01-01 05:00:00, 2013-01-01 05:00:…
```

두번째로, 어떤 변수는 모델의 설명변수는 아니지만, 잘 맞지 않는 데이터포인트들을 살펴보는데 사용할 수 있습니다. 
우리 데이터에서 이러한 식별변수로 사용하고 싶은 변수가 두 개 있습니다. 
수치형 값인 `flight` 와, 데이트-타임형 값인 `time_hour` 입니다.

세번째로, `dest` 에는 104 개의 도착지가 있고 `carrier` 에는 16 개의 다른 항공사 정보가 있습니다. 


```r
flight_data %>% 
  skimr::skim(dest, carrier) 
```


<table style='width: auto;'
        class='table table-condensed'>
<caption>Table 1: Data summary</caption>
 <thead>
  <tr>
   <th style="text-align:left;">   </th>
   <th style="text-align:left;">   </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> Name </td>
   <td style="text-align:left;"> Piped data </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Number of rows </td>
   <td style="text-align:left;"> 325819 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Number of columns </td>
   <td style="text-align:left;"> 10 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> _______________________ </td>
   <td style="text-align:left;">  </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Column type frequency: </td>
   <td style="text-align:left;">  </td>
  </tr>
  <tr>
   <td style="text-align:left;"> factor </td>
   <td style="text-align:left;"> 2 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ________________________ </td>
   <td style="text-align:left;">  </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Group variables </td>
   <td style="text-align:left;"> None </td>
  </tr>
</tbody>
</table>


**Variable type: factor**

<table>
 <thead>
  <tr>
   <th style="text-align:left;"> skim_variable </th>
   <th style="text-align:right;"> n_missing </th>
   <th style="text-align:right;"> complete_rate </th>
   <th style="text-align:left;"> ordered </th>
   <th style="text-align:right;"> n_unique </th>
   <th style="text-align:left;"> top_counts </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> dest </td>
   <td style="text-align:right;"> 0 </td>
   <td style="text-align:right;"> 1 </td>
   <td style="text-align:left;"> FALSE </td>
   <td style="text-align:right;"> 104 </td>
   <td style="text-align:left;"> ATL: 16771, ORD: 16507, LAX: 15942, BOS: 14948 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> carrier </td>
   <td style="text-align:right;"> 0 </td>
   <td style="text-align:right;"> 1 </td>
   <td style="text-align:left;"> FALSE </td>
   <td style="text-align:right;"> 16 </td>
   <td style="text-align:left;"> UA: 57489, B6: 53715, EV: 50868, DL: 47465 </td>
  </tr>
</tbody>
</table>

단순로지스틱 회귀모형에서 `dest`, `carrier` 변수는 [더미 변수](https://bookdown.org/max/FES/creating-dummy-variables-for-unordered-categories.html) 로 변환될 것입니다. 
하지만, 변수값들 중 자주 나타나지는 않는 값이 있는 경우에는 분석이 복잡해질 수 있습니다. 
이번 장 후반에서 모델링하기 전에 특수한 단계를 추가하여 이러한 이슈를 해결하는 것에 대해 논의할 것입니다.

## 데이터 나누기 {#data-split}

이제 본격적으로, 데이터셋을 _트레이닝셋_ 과 _테스팅셋_ , 둘로 나누는 것부터 시작해봅시다. 
원본 데이터셋 대부분의 행들을 _트레이닝셋_ (임의로 선택한 서브셋)으로 사용할 것입니다. 
트레이닝 데이터는 모델을 *적합(fit)* 하는데 사용할 것이고 _테스팅_ 셋은 모델 성능을 측정하는데에 사용될 것입니다.

[rsample](https://rsample.tidymodels.org/) 패키지를 사용하여 데이터를 나누는 정보가 있는 객체를 생성할 것입니다. 그리고 rsample 함수 두 개를 사용하여 트레이닝셋과 테스팅셋 데이터프레임을 생성할 것입니다.


```r
# Fix the random numbers by setting the seed 
# This enables the analysis to be reproducible when random numbers are used 
set.seed(222)
# Put 3/4 of the data into the training set 
data_split <- initial_split(flight_data, prop = 3/4)

# Create data frames for the two sets:
train_data <- training(data_split)
test_data  <- testing(data_split)
```

 
## recipe 와 role 생성하기 {#recipe}

단순로지스틱 회귀모델을 위한 레시피를 생성하는 것으로 시작해 봅시다. 모델을 훈련시키기 전에 레시피를 사용하여 새로운 설명변수 몇개를 생성하고 모델이 요구하는 전처리들을 수행할 수 있습니다.

새로운 레시피를 만들어 봅시다: 


```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) 
```

[`recipe()` 함수](https://recipes.tidymodels.org/reference/recipe.html) 는 다음과 같이 두 개의 인수를 취하는 것을 볼 수 있습니다.

+ **공식**. 틸더 (`~`) 왼쪽의 변수들은 모델 종속변수 (여기에서 `arr_delay`) 가 있고, 오른쪽에는 설명변수들이 있습니다. 변수들은 이름으로 나열하거나, 점 (`.`) 을 사용하여 나머지 변수 모두를 가리킬 수 있습니다.

+ **데이터**. 레시피는 모델을 생성하기 위해 사용하는 데이터셋과 연관됩니다. 이러한 데이터셋은 일반적으로 _트레이닝_ 셋이 되는데, 따라서 여기에서는 `data = train_data` 이 됩니다. 데이터셋의 이름을 바꾸는 것은 실제로 데이터를 변형하지는 않습니다: 변수의 이름과, 팩터형, 정수형, 데이트형 등과 같은 유형을 카탈로그하는데 사용됩니다.

이제 이 레시피에 [롤(roles)](https://recipes.tidymodels.org/reference/roles.html) 을 추가할 수 있습니다. [`update_role()` 함수](https://recipes.tidymodels.org/reference/roles.html) 를 사용하여 `flight` 와 `time_hour` 는 `"ID"` (역할은 임의의 문자값을 가질 수 있음) 라는 이름의 커스텀 역할을 가진 변수라고 명시할 수 있습니다. 공식에서는 트레이닝셋에서 `arr_delay` 를 제외한 모든 변수들을 포함했지만, 레시피를 만들 때는 이 두 변수들을 놓아두되, 종속변수나 설명변수로 사용하지 말라고 명시합니다.


```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) %>% 
  update_role(flight, time_hour, new_role = "ID") 
```

이렇게 레시피에 롤을 추가하는 것은 선택사항입니다. 
여기에서 롤을 사용하는 목적은 이러한 두개의 변수들은 데이터에 포함되지만 모델에 포함되지는 않을 것이기 때문입니다. 
모델이 적합된 이후에 예측값이 잘 맞지 않는 값들을 조사하고 싶을 때 편리할 수 있습니다. 
이러한 ID 열들을 사용할 수 있을 것이고, 잘못된 점을 이해하는 데에 사용될 수 있습니다.

`summary()` 함수를 사용하여 현재의 변수와 역할을 봅시다:


```r
summary(flights_rec)
#> # A tibble: 10 × 4
#>    variable  type    role      source  
#>    <chr>     <chr>   <chr>     <chr>   
#>  1 dep_time  numeric predictor original
#>  2 flight    numeric ID        original
#>  3 origin    nominal predictor original
#>  4 dest      nominal predictor original
#>  5 air_time  numeric predictor original
#>  6 distance  numeric predictor original
#>  7 carrier   nominal predictor original
#>  8 date      date    predictor original
#>  9 time_hour date    ID        original
#> 10 arr_delay nominal outcome   original
```


## 피쳐 생성하기 {#features}

파이프 연산자를 사용하여 단계들을 레시피에 추가할 수 있습니다. 
항공편 날짜가 연착 가능성에 영향을 주는 것은 아마도 합리적일 것입니다. 모델을 개선하려면 약간 **피쳐 엔지니어링** 을 하는 것이 중요합니다. 날짜를 어떻게 인코딩해야 할까요? 
`date` 열은 R `date` 객체를 가지기 때문에, 이 컬럼을 "있는 그대로" 포함하면, 기준날짜 이후 날 수와 같은 날짜 포맷으로 변환할 것입니다:


```r
flight_data %>% 
  distinct(date) %>% 
  mutate(numeric_date = as.numeric(date)) 
#> # A tibble: 364 × 2
#>   date       numeric_date
#>   <date>            <dbl>
#> 1 2013-01-01        15706
#> 2 2013-01-02        15707
#> 3 2013-01-03        15708
#> 4 2013-01-04        15709
#> 5 2013-01-05        15710
#> # … with 359 more rows
```

수치형 날짜 변수는 모델링에 좋은 방법일 수 있습니다: 이러한 모델은 연착의 로그오즈와 수치형 날짜변수 사이의 선형 경향성을 가질 수 있어 장점을 가질 수 있습니다. 
하지만, 날짜 _파생_ 항(term)들을 모델에 추가하는 것이 더 좋을 것입니다. 예를 들어 `date` 변수 하나로부터 다음과 같이 의미있는 피쳐들을 도출할 수 있습니다: 

* 요일,
 
* 달,
 
* 해당날짜가 공휴일인지 여부. 
 
우리 레시피에 이 세 작업에 해당하는 단계를 추가해 봅시다:



```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) %>% 
  update_role(flight, time_hour, new_role = "ID") %>% 
  step_date(date, features = c("dow", "month")) %>%               
  step_holiday(date, 
               holidays = timeDate::listHolidays("US"), 
               keep_original_cols = FALSE)
```

각 단계가 어떤 작업을 한 걸까요?

* [`step_date()`](https://recipes.tidymodels.org/reference/step_date.html) 에서, 새로운 두 팩터형 열을 적절한 요일과 월을 가진 두 개의 열을 생성했습니다. 

* [`step_holiday()`](https://recipes.tidymodels.org/reference/step_holiday.html)에서, 해당되는 날짜가 휴일인지 아닌지를 가리키는 바이너리 변수를 생성했습니다. 인수값 `timeDate::listHolidays("US")` 를 인수값으로 하면 [timeDate 패키지](https://cran.r-project.org/web/packages/timeDate/index.html) 를 사용하여 17 개의 표준 미국 공휴일을 나열합니다.

* `keep_original_cols = FALSE` 를 하여, `date` 변수가 모델에 더 이상 필요하지 않기 때문에 제거합니다. 새로운 변수를 생성하는 레시피 단계들 대부분은 이 인수를 가집니다.

다음으로, 설명변수들의 변수 타잎에 집중해 봅시다. 
로지스틱 회귀모형을 훈련할 것이기 때문에, 설명변수들이 궁극적으로는 문자열이나 팩터형 변수들 같은 명목형 데이터가 아닌 수치형 데이터가 될 것입니다. 
다른 말로 하면, 데이터를 저장하는 방식(데이터프레임 안에서의 팩터형으로) 과 공식들이 사용하는 방식 (수치형 행렬) 에서 차이가 있을 수 있습니다.

`dest` 와 `origin` 같은 팩터형에 대해, [표준 방법](https://bookdown.org/max/FES/creating-dummy-variables-for-unordered-categories.html) 은 이 변수들을 _더미_ 나 _indicator_ 변수들로 변환하여 수치형으로 만드는 것입니다. 
팩터형의 각 수준에 대해 이진 값들이 됩니다. 
예를 들어 우리 `origin` 변수는 `"EWR"`, `"JFK"`, `"LGA"` 값을 갖습니다. 아래에 나온 표준 더미변수 인코딩 방법을 적용하며, origin 공항이 `"JFK"` 나 `"LGA"` 이면 각각 1, 그 외에는 0 인 수치형 열 _두 개_ 가 만들어 질 것입니다.




<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
  <tr>
   <th style="text-align:left;"> origin </th>
   <th style="text-align:right;"> origin_JFK </th>
   <th style="text-align:right;"> origin_LGA </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> JFK </td>
   <td style="text-align:right;"> 1 </td>
   <td style="text-align:right;"> 0 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> EWR </td>
   <td style="text-align:right;"> 0 </td>
   <td style="text-align:right;"> 0 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> LGA </td>
   <td style="text-align:right;"> 0 </td>
   <td style="text-align:right;"> 1 </td>
  </tr>
</tbody>
</table>


하지만, 이러한 표준 모델 공식과 다르게 레시피는 자동으로 이러한 더미 변수들을 만들어 제공하지 **않습니다**. 이 단계를 추가하라고 명시해야 합니다. 
두가지 이유가 있습니다. 
첫번째로는, [수치형 설명변수](https://bookdown.org/max/FES/categorical-trees.html) 를 필요로 하지 않는 모델들이 많기 때문에, 더미 변수들이 항상 선호되는 것은 아닐 수 있습니다. 
두번째 이유는 모델링 이외의 목적으로도 레시피를 사용할 수 있는데, 더미 버전이 아닌 변수들이 더 좋을 수 있습니다. 
예를 들어, 하나의 팩터형으로서 표나 플롯을 그리고 싶을 수 있습니다. 이러한 이유로 `step_dummy()` 을 사용하여 더미 변수를 만들라고 명시적으로 알려주어야 합니다. 


```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) %>% 
  update_role(flight, time_hour, new_role = "ID") %>% 
  step_date(date, features = c("dow", "month")) %>%               
  step_holiday(date, 
               holidays = timeDate::listHolidays("US"), 
               keep_original_cols = FALSE) %>% 
  step_dummy(all_nominal_predictors())
```

앞에서와 다르게 한 것이 있습니다. 변수들마다 단계를 개별적으로 적용한 것 대신 [selectors](https://recipes.tidymodels.org/reference/selections.html), `all_nominal_predictors()` 를 사용하여 동시에 여러 변수에게 대해 레시피 단계를 적용했습니다. 
[selector 함수들](https://recipes.tidymodels.org/reference/selections.html) 을 조합하여 변수들의 교집합을 선택할 수 있습니다.

위의 단계에서 `origin`, `dest`, `carrier` 변수가 선택됩니다. 
이전의 `step_date()` 이 만든 두 개의 새로운 변수, `date_dow`, `date_mont` 도 포함됩니다.

더 일반적으로, 레시피 셀렉터는 단계를 한번에 변수 하나씩 적용할 필요는 없다는 것을 의미합니다. 
레시피는 각 열의 _변수유형_ 과 _롤_ 을 알고 있기 때문에, 이 정보를 이용하여 변수들을 선택하거나 뺄 수 있습니다.

우리 레시피에 마지막 단계를 추가해야 합니다. 
`carrier` 와 `dest` 는 가끔씩 일어나는 팩터형 값을 가지기 때문에, 트레이닝셋에 존재하지 않는 값에 대해 더미변수를 생성해야 할 수 있습니다. 예를 들어, 테스트셋에만 존재하는 목적지가 있습니다: 


```r
test_data %>% 
  distinct(dest) %>% 
  anti_join(train_data)
#> Joining, by = "dest"
#> # A tibble: 1 × 1
#>   dest 
#>   <fct>
#> 1 LEX
```

레시피가 훈련셋에 적용될 때, 팩터 레벨이 `flight_data` (트레이닝 셋이 아님) 에서 생성되기 때문에, LEX 에 해당하는 열이 만들어지지만 이 열은 모두 0 을 가지고 있습니다. 이는 열 안에서 정보가 없는 "영분산(zero-variance) 설명변수" 입니다.
이러한 설명변수에 대해 에러를 발생시키지 않는 R 함수들이 있지만, 보통은 경고와 다른 이슈들을 만듭니다.
`step_zv()` 은 트레이닝셋 데이터가 하나의 값을 가질 때 열을 제거하기 때문에, `step_dummy()` *이후*에 레시피에 추가해야 합니다:


```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) %>% 
  update_role(flight, time_hour, new_role = "ID") %>% 
  step_date(date, features = c("dow", "month")) %>%               
  step_holiday(date, 
               holidays = timeDate::listHolidays("US"), 
               keep_original_cols = FALSE) %>% 
  step_dummy(all_nominal_predictors()) %>% 
  step_zv(all_predictors())
```

이제 데이터에 필요한 작업 _specification_ 을 생성했습니다. 만든 레시피를 어떻게 사용할까요?

## 레시피로 모델 적합하기 {#fit-workflow}

로지스틱 회귀를 사용하여 항공기 데이터를 모델링해 봅시다. [*모델 만들기*](/start/models/) 에서 배웠듯이, parsnip 패키지를 사용하여  [모델 스펙 정의하기](/start/models/#build-model) 부터 시작합니다: 


```r
lr_mod <- 
  logistic_reg() %>% 
  set_engine("glm")
```


우리 모델을 훈련하고 테스트하면서 몇 단계에 레시피를 사용하게 될 것입니다. 

1. **트레이닝셋을 사용하여 레시피를 프로세스하기**: 트레이닝셋에 기반하여 추정이나 계산을 하는 것이 포함됩니다. 
우리 레시피에게 있어, 트레이닝셋을 사용하여 어떤 설명변수가 더미 변수로 변환되어야 하는지, 어떤 설명변수가 트레이닝셋에서 영분산이 되어 제거를 고려해야 하는지를 결정할 것입니다. 
 
1. **트레이닝셋에 레시피 적용하기**: 트레이닝셋의 최종 설명변수를 만듭니다.
 
1. **테스트셋에 레시피 적용하기**: 테스트셋에 최종 설명변수 셋을 생성합니다. 
새로 계산 되는 것은 없고, 테스트셋 정보는 여기에서 사용되지 않습니다; 트레이닝셋에서 더미변수와 영분산 결과가 테스트셋에 적용됩니다.

_모델 워크플로_ 를 사용하면 이 과정이 단순화되는데, 모델과 레시피 쌍을 결합합니다. 
모델들은 해당하는 레시피가 필요한 경우가 많아, 모델과 레시피를 묶어 _워크플로_로 훈련하고 테스트하는 것이 더 쉽습니다. tidymodels 의 [workflows 패키지](https://workflows.tidymodels.org/) 를 사용하여 우리 parsnip 모델(`lr_mod`)과 레시피(`flights_rec`)를 결합할 것입니다.


```r
flights_wflow <- 
  workflow() %>% 
  add_model(lr_mod) %>% 
  add_recipe(flights_rec)

flights_wflow
#> ══ Workflow ══════════════════════════════════════════════════════════
#> Preprocessor: Recipe
#> Model: logistic_reg()
#> 
#> ── Preprocessor ──────────────────────────────────────────────────────
#> 4 Recipe Steps
#> 
#> • step_date()
#> • step_holiday()
#> • step_dummy()
#> • step_zv()
#> 
#> ── Model ─────────────────────────────────────────────────────────────
#> Logistic Regression Model Specification (classification)
#> 
#> Computational engine: glm
```

이제 결과의 설명변수에서부터 레시피를 준비하고 모델을 훈련시키는데 사용할 수 있는 함수 하나가 생겼습니다: 


```r
flights_fit <- 
  flights_wflow %>% 
  fit(data = train_data)
```
 
이 객체 내부에는 최종마무리된 레시피와 적합된 모델 객체가 있습니다. 
이 워크플로에서 모델이나 레시피를 추출하고자 할 수 있습니다. 
도우미 함수들, `extract_fit_parsnip()` 와 `extract_recipe()` 를 사용하면 됩니다. 
예를 들어, 여기서 적합된 모델 객체를 추출한 후 `broom::tidy()` 함수를 사용하여 모델 계수의 타이디 티블을 얻습니다.


```r
flights_fit %>% 
  extract_fit_parsnip() %>% 
  tidy()
#> # A tibble: 157 × 5
#>   term                estimate std.error statistic  p.value
#>   <chr>                  <dbl>     <dbl>     <dbl>    <dbl>
#> 1 (Intercept)          7.28    2.73           2.67 7.64e- 3
#> 2 dep_time            -0.00166 0.0000141   -118.   0       
#> 3 air_time            -0.0440  0.000563     -78.2  0       
#> 4 distance             0.00507 0.00150        3.38 7.32e- 4
#> 5 date_USChristmasDay  1.33    0.177          7.49 6.93e-14
#> # … with 152 more rows
```

## 훈련된 워크플로를 사용하여 예측하기 {#predict-workflow}

우리 목적은 한 여객기가 30 분 이상 연착할지를 예측하는 것이었습니다. 우리는 방금 끝낸 일은:

1. 모델 만들기 (`lr_mod`),

1. 전처리 레시피생성하기 (`flights_rec`),

1. 모델과 레시피 묶기 (`flights_wflow`),

1. `fit()` 호출을 이용하여 우리 워크플로 훈련하기. 

다음 단계는 훈련된 워크플로 (`flights_fit`) 를 사용하여, 사용하지 않은 테스트 데이터에 대해 예측을 하는 것인데, 단일 호출 `predict()` 로 할 수 있습니다. `predict()` 를 하면 레시피를 새 데이터에 적용한 후, 이를 적합된 모델에 전달합니다. 


```r
predict(flights_fit, test_data)
#> # A tibble: 81,455 × 1
#>   .pred_class
#>   <fct>      
#> 1 on_time    
#> 2 on_time    
#> 3 on_time    
#> 4 on_time    
#> 5 on_time    
#> # … with 81,450 more rows
```

종속 변수가 팩터형이기 때문에, `predict()` 의 출력값은 예측 범주: `late` 대 `on_time` 를 반환합니다. 
하지만, 각 항공편에 대해 예측범주 확률을 원한다고 합시다. 
이들을 반환받는 법으로는 `predict()` 에 `type = "prob"` 로 명시하거나 `augment()` 를 모델과 테스트데이터와 함께 사용하여 이들을 함께 저장하면 됩니다.


```r
flights_aug <- 
  augment(flights_fit, test_data)

# The data look like: 
flights_aug %>%
  select(arr_delay, time_hour, flight, .pred_class, .pred_on_time)
#> # A tibble: 81,455 × 5
#>   arr_delay time_hour           flight .pred_class .pred_on_time
#>   <fct>     <dttm>               <int> <fct>               <dbl>
#> 1 on_time   2013-01-01 05:00:00   1545 on_time             0.945
#> 2 on_time   2013-01-01 05:00:00   1714 on_time             0.949
#> 3 on_time   2013-01-01 06:00:00    507 on_time             0.964
#> 4 on_time   2013-01-01 06:00:00   5708 on_time             0.961
#> 5 on_time   2013-01-01 06:00:00     71 on_time             0.962
#> # … with 81,450 more rows
```

이제 예측 클래스 확률이 있는 티블을 얻었는데, 우리 워크플로의 성능을 어떻게 측정할 수 있을까요? 
처음 몇 행을 보면 다섯개 정시비행의 `.pred_on_time` 의 값이 *p* > .50 이므로 우리모델이 정확하게 예측했다는 것을 알 수 있습니다. 
하지만 전체 예측해야할 행은 모두 81,455 행입니다. 
우리 모델이 반응 변수, `arr_delay` 의 실제값에 비해 연착을 얼마나 잘 예측했는지를 나타내는 지표를 계산하고 싶습니다. 

[yardstick 패키지](https://yardstick.tidymodels.org/)에 있는 `roc_curve()` 과 `roc_auc()` 로 계산한 area under the [ROC curve](https://bookdown.org/max/FES/measuring-performance.html#class-metrics) 을 우리의 지표로 사용해 봅시다.

ROC커브를 생성하기 위해, 위의 코드청크에서 계산한, `late` 과 `on_time` 에 해당하는 예측 클래스 확률이 필요합니다. `roc_curve()` 을 사용한 후 `autoplot()` 메소드에 파이프를 하여 이 값들로 ROC커브를 생성할 수 있습니다:


```r
flights_aug %>% 
  roc_curve(truth = arr_delay, .pred_late) %>% 
  autoplot()
```

<img src="figs/roc-plot-1.svg" width="672" />

비슷하게, `roc_auc()` 은 area under the curve 를 추정합니다: 


```r
flights_aug %>% 
  roc_auc(truth = arr_delay, .pred_late)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.764
```

그리 나쁘지 않네요! 
이 레시피를 [*사용하지 않은*](https://workflows.tidymodels.org/reference/add_formula.html) 다음의 워크플로도 한 번 시도해보길 바랍니다. `workflows::add_formula(arr_delay ~ .)` 를 `add_recipe()` 대신 사용하고 (식별 변수를 먼저 제거하는 걸 잊지 말 것!), 우리의 레시피가 모델의 연착 예측력을 개선했는지 보면 됩니다.


```r
set.seed(555)
flights_cens <- flight_data %>% 
  select(-flight, -time_hour)

flights_cens_split <- initial_split(flights_cens, prop = 3/4)
flights_cens_train <- training(flights_cens_split)
flights_cens_test <- testing(flights_cens_split)

flights_wflow_raw <-
  workflow() %>% 
  add_model(lr_mod) %>% 
  add_formula(arr_delay ~ .)

flights_fit_raw <- 
  flights_wflow_raw %>% 
  fit(data = flights_cens_train)

flights_preds_raw <- 
  predict(flights_fit_raw, 
          flights_cens_test, 
          type = "prob") %>% 
  bind_cols(flights_cens_test %>% select(arr_delay)) 

flights_preds_raw %>% 
  roc_auc(truth = arr_delay, .pred_late)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.735
```


## 세션정보 {#session-info}


```
#> ─ Session info  😻  🐕  😾   ───────────────────────────────────────
#>  hash: smiling cat with heart-eyes, dog, pouting cat
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
#>  date     2022-01-16
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package      * version date (UTC) lib source
#>  broom        * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials        * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr        * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2      * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer        * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  nycflights13 * 1.0.2   2021-04-12 [1] CRAN (R 4.1.0)
#>  parsnip      * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr        * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes      * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang          0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
#>  rsample      * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  skimr        * 2.1.3   2021-03-07 [1] CRAN (R 4.1.0)
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
