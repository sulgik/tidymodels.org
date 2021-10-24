---
title: "recipe 로 데이터 전처리하기"
weight: 2
tags: [recipes, parsnip, workflows, yardstick, broom]
categories: [pre-processing]
description: | 
  Prepare data for modeling with modular preprocessing steps.
---
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />





## 들어가기 {#intro}

[*모델 만들기*](/start/models/) 챕터에서는 [parsnip 패키지](https://parsnip.tidymodels.org/) 를 사용하여 여러 엔진들로 모델을 정의하고 훈련시키는 법에 대해 배웠습니다. 이 챕터에서는 tidymodels 의 또 다른 패키지인 [recipes](https://recipes.tidymodels.org/) 패키지를 살펴볼 것인데, 트레이닝 *전*에 데이터를 전처리를 도와주기 위해 설계되었습니다. Recipes 는 다음과 같이 일련의 전처리 과정들로 구성됩니다:

+ 정성 설명변수를 지시변수 (indicator variables 더미 변수로도 알려짐) 로 변환,

+ 데이터를 다른 스케일로 변환 (예, 변수에 로그를 취함),

+ 설명변수들의 그룹을 모두 변환,

+ 원 변수들로 부터 핵심 변수를 추출 (예, 날짜에서 요일을 추출),

등입니다. If you are familiar with R's formula interface, a lot of this might sound familiar and like what a formula already does. Recipes can be used to do many of the same things, but they have a much wider range of possibilities. This article shows how to use recipes for modeling. 

To use code in this article,  you will need to install the following packages: nycflights13, skimr, and tidymodels.


```r
library(tidymodels)      # for the recipes package, along with the rest of tidymodels

# Helper packages
library(nycflights13)    # for flight data
library(skimr)           # for variable summaries
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 뉴욕시 항공기 데이터 {#data}



[nycflights13 data](https://github.com/hadley/nycflights13) 를 사용하여 여객기가 30 분 이상 연착될지를 예측해봅시다. 이 데이터에는 뉴욕시 인근에서 출발하는 여객기 325,819 편에 대한 정보가 있습니다. 우선 데이터를 로드하고 변수에 수정을 몇 개 합시다.


```r
set.seed(123)

flight_data <- 
  flights %>% 
  mutate(
    # Convert the arrival delay to a factor
    arr_delay = ifelse(arr_delay >= 30, "late", "on_time"),
    arr_delay = factor(arr_delay),
    # We will use the date (not date-time) in the recipe below
    date = lubridate::as_date(time_hour)
  ) %>% 
  # Include the weather data
  inner_join(weather, by = c("origin", "time_hour")) %>% 
  # Only retain the specific columns we will use
  select(dep_time, flight, origin, dest, air_time, distance, 
         carrier, date, arr_delay, time_hour) %>% 
  # Exclude missing data
  na.omit() %>% 
  # For creating models, it is better to have qualitative columns
  # encoded as factors (instead of character strings)
  mutate_if(is.character, as.factor)
```


We can see that about 16% of the flights in this data set arrived more than 30 minutes late. 


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


Before we start building up our recipe, let's take a quick look at a few specific variables that will be important for both preprocessing and modeling.

First, notice that the variable we created called `arr_delay` is a factor variable; it is important that our outcome variable for training a logistic regression model is a factor.


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

Second, there are two variables that we don't want to use as predictors in our model, but that we would like to retain as identification variables that can be used to troubleshoot poorly predicted data points. These are `flight`, a numeric value, and `time_hour`, a date-time value.

Third, there are 104 flight destinations contained in `dest` and 16 distinct `carrier`s. 


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


Because we'll be using a simple logistic regression model, the variables `dest` and `carrier` will be converted to [dummy variables](https://bookdown.org/max/FES/creating-dummy-variables-for-unordered-categories.html). However, some of these values do not occur very frequently and this could complicate our analysis. We'll discuss specific steps later in this article that we can add to our recipe to address this issue before modeling. 

## 데이터 나누기 {#data-split}

이제 본격적으로, 데이터셋을 _트레이닝_셋과 _테스팅_셋, 둘로 나누는 것으로 시작해봅시다. We'll keep most of the rows in the original dataset (subset chosen randomly) in the _training_ set. The training data will be used to *fit* the model, and the _testing_ set will be used to measure model performance. 

To do this, we can use the [rsample](https://rsample.tidymodels.org/) package to create an object that contains the information on _how_ to split the data, and then two more rsample functions to create data frames for the training and testing sets: 


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

To get started, let's create a recipe for a simple logistic regression model. Before training the model, we can use a recipe to create a few new predictors and conduct some preprocessing required by the model. 

Let's initiate a new recipe: 


```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) 
```

[`recipe()` 함수](https://recipes.tidymodels.org/reference/recipe.html) 는 인수 둘을 취하는 것을 볼 수 있습니다.

+ A **formula**. Any variable on the left-hand side of the tilde (`~`) is considered the model outcome (here, `arr_delay`). On the right-hand side of the tilde are the predictors. Variables may be listed by name, or you can use the dot (`.`) to indicate all other variables as predictors.

+ The **data**. A recipe is associated with the data set used to create the model. This will typically be the _training_ set, so `data = train_data` here. Naming a data set doesn't actually change the data itself; it is only used to catalog the names of the variables and their types, like factors, integers, dates, etc.

이제 이 recipe 에 [roles(역할)](https://recipes.tidymodels.org/reference/roles.html) 을 추가할 수 있습니다. [`update_role()` 함수](https://recipes.tidymodels.org/reference/roles.html) 를 사용하여 `flight` 와 `time_hour` 는 `"ID"` (역할은 임의의 문자값을 가질 수 있음) 라는 이름의 커스텀 역할을 가진 변수라고 recipe 에 명시할 수 있습니다. 공식에서는 트레이닝셋에서 `arr_delay` 를 제외한 모든 변수들을 포함했지만, recipe 에게 이 두 변수들을 놓아두되, 종속변수나 설명변수로 사용하지 말라고 명시합니다.


```r
flights_rec <- 
  recipe(arr_delay ~ ., data = train_data) %>% 
  update_role(flight, time_hour, new_role = "ID") 
```

This step of adding roles to a recipe is optional; the purpose of using it here is that those two variables can be retained in the data but not included in the model. This can be convenient when, after the model is fit, we want to investigate some poorly predicted value. These ID columns will be available and can be used to try to understand what went wrong.

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

Now we can start adding steps onto our recipe using the pipe operator. Perhaps it is reasonable for the date of the flight to have an effect on the likelihood of a late arrival. A little bit of **feature engineering** might go a long way to improving our model. How should the date be encoded into the model? The `date` column has an R `date` object so including that column "as is" will mean that the model will convert it to a numeric format equal to the number of days after a reference date: 


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

It's possible that the numeric date variable is a good option for modeling; perhaps the model would benefit from a linear trend between the log-odds of a late arrival and the numeric date variable. However, it might be better to add model terms _derived_ from the date that have a better potential to be important to the model. 예를 들어 `date` 변수 하나로부터 다음과 같이 의미있는 피쳐들을 도출할 수 있습니다: 

* 요일,
 
* 달,
 
* 해당날짜가 공휴일인지 여부. 
 
이 세 작업을 위해 우리 recipe 에 단계를 추가해 봅시다:



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

* With [`step_date()`](https://recipes.tidymodels.org/reference/step_date.html), we created two new factor columns with the appropriate day of the week and the month. 

* With [`step_holiday()`](https://recipes.tidymodels.org/reference/step_holiday.html), we created a binary variable indicating whether the current date is a holiday or not. The argument value of `timeDate::listHolidays("US")` uses the [timeDate package](https://cran.r-project.org/web/packages/timeDate/index.html) to list the 17 standard US holidays.

* With `keep_original_cols = FALSE`, we remove the original `date` variable since we no longer want it in the model. Many recipe steps that create new variables have this argument.

다음으로, 설명변수들의 변수 타잎에 집중해 봅시다. 로지스틱 회귀 모형을 훈련할 것이기 때문에, 설명변수들이 궁극적으로는 문자열이나 요인 변수들 같은 명목형 데이터가 아닌 수치형 데이터가 될 것입니다. 다른 말로 하면, 데이터를 저장하는 방식(데이터프레임 안에서의 팩터형으로) 과  밑에서 돌아가는 공식들이 사용하는 방식 (수치형 행렬) 에서 차이가 있을 수 있습니다.

`dest` 와 `origin` 같은 팩터형에 대해, [표준 방법](https://bookdown.org/max/FES/creating-dummy-variables-for-unordered-categories.html) 은 이 변수들을 _더미_ 나 _indicator_ 변수들로 변환하여 수치형으로 만드는 것입니다. 이 방법은 팩텨형의 각 수준에 대해 이진 값들입니다. 예를 들어 우리 `origin` 변수가 `"EWR"`, `"JFK"`, `"LGA"` 값을 갖습니다. 아래에 나온 표준 더미 변수 인코딩 방법은 각각, 본 공항이 `"JFK"` 나 `"LGA"` 이면 1, 그 외에는 0인 수치형 _두개_의 열이 만들어 질 것입니다.




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


하지만, 이러한 표준 모델 공식과 다르게 recipe 는 자동으로 이러한 더미 변수들을 만들어 제공하지 **않습니다**. recipe 에게 이 단계를 추가하라고 명시해야 합니다. 두가지 이유가 있습니다. 첫번째 이유는 [수치형 설명변수](https://bookdown.org/max/FES/categorical-trees.html) 를 필요로 하지 않는 모델들이 많기 때문에, 더미 변수들이 항상 선호되는 것은 아닐 수 있습니다. 두번째 이유는 recipe 는 모델링 이외의 목적으로 사용될 수 있는데, 더미 버전이 아닌 변수들이 더 좋을 수 있습니다. 예를 들어, 하나의 팩터형으로서 표나 플롯을 그리고 싶을 수 있습니다. 이러한 이유로 recipe 에게 `step_dummy()` 을 사용하여 더미 변수들을 만들라고 명시적으로 알려주어야 합니다. 


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

여기에서 전과 다르게 한 것이 있습니다. 개별 변수들에게 단계를 적용한 것 대신 [selectors](https://recipes.tidymodels.org/reference/selections.html), `all_nominal_predictors()` 를 사용하여 recipe 단계를 동시에 여러 변수들에게 적용했습니다. [selector 함수들](https://recipes.tidymodels.org/reference/selections.html) 을 조합하여 변수들의 교집합을 선택할 수 있습니다.

At this stage in the recipe, this step selects the `origin`, `dest`, and `carrier` variables. It also includes two new variables, `date_dow` and `date_month`, that were created by the earlier `step_date()`. 

More generally, the recipe selectors mean that you don't always have to apply steps to individual variables one at a time. Since a recipe knows the _variable type_ and _role_ of each column, they can also be selected (or dropped) using this information. 

We need one final step to add to our recipe. Since `carrier` and `dest` have some infrequently occurring factor values, it is possible that dummy variables might be created for values that don't exist in the training set. For example, there is one destination that is only in the test set: 


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

When the recipe is applied to the training set, a column is made for LEX because the factor levels come from `flight_data` (not the training set), but this column will contain all zeros. This is a "zero-variance predictor" that has no information within the column. While some R functions will not produce an error for such predictors, it usually causes warnings and other issues. `step_zv()` will remove columns from the data when the training set data have a single value, so it is added to the recipe *after* `step_dummy()`: 


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

이제 데이터에 필요한 작업 _specification_ 을 생성했습니다. 우리가 만든 recipe 를 어떻게 사용할까요?

## Recipe 로 모델 적합하기 {#fit-workflow}

로지스틱 회귀를 사용하여 항공기 데이터를 모델링해 봅시다. [*모델 만들기*](/start/models/) 에서 배웠듯이, parsnip 패키지를 사용하여  [모델 스펙 정의하기](/start/models/#build-model) 부터 시작합니다: 


```r
lr_mod <- 
  logistic_reg() %>% 
  set_engine("glm")
```


우리 모델을 훈련하고 테스트하면서 몇 단계에 recipe 를 사용하게 될 것입니다. 

1. **트레이닝셋을 사용하여 recipe 를 프로세스한다**: 트레이닝셋에 기반하여 추정이나 계산을 하는 것이 포함됩니다. 우리 recipe 에게 있어, 트레이닝셋을 사용하여 어떤 설명변수가 더미 변수로 변환되어야 하는지, 어떤 설명변수가 트레이닝셋에서 영분산이 되어 제거를 고려해야 하는지를 결정할 것입니다. 
 
1. **트레이닝셋에 recipe 적용하기**: 트레이닝셋의 최종 설명변수를 만듭니다.
 
1. **테스트셋에 recipe 적용하기**: We create the final predictor set on the test set. Nothing is recomputed and no information from the test set is used here; the dummy variable and zero-variance results from the training set are applied to the test set. 
 
To simplify this process, we can use a _모델 워크플로_, which pairs a model and recipe together. This is a straightforward approach because different recipes are often needed for different models, so when a model and recipe are bundled, it becomes easier to train and test _workflows_. tidymodels 의 [workflows 패키지](https://workflows.tidymodels.org/) 를 사용하여 우리 parsnip 모델 (`lr_mod`) 과 우리 recipe (`flights_rec`) 를 묶을 것입니다.


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

Now, there is a single function that can be used to prepare the recipe and train the model from the resulting predictors: 


```r
flights_fit <- 
  flights_wflow %>% 
  fit(data = train_data)
```
 
이 객체 내부에는 최종마무리된 recipe 와 적합된 model 객체가 있습니다. 이 워크플로에서 모델이나 recipe 를 추출하고자 할 수 있습니다. 도우미 함수들, `extract_fit_parsnip()` 와 `extract_recipe()` 를 사용하면 됩니다. 예를 들어, 여기서 적합된 모델 객체를 추출한 후 `broom::tidy()` 함수를 사용하여 모델 계수의 타이디 티블을 얻습니다.


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

우리 목적은 한 여객기가 30분 이상 연착할지를 예측하는 것이었습니다. 우리는 방금 끝낸 일은:

1. 모델 만들기 (`lr_mod`),

1. 전처리 recipe 생성하기 (`flights_rec`),

1. model 과 recipe 묶기 (`flights_wflow`),

1. `fit()` 호출 하나를 이용하여 우리 워크플로 훈련하기. 

다음 단계는 훈련된 워크플로 (`flights_fit`) 를 사용하여 사용하지 않은 테스트 데이터에 대해 예측을 하는 것인데, 단일 호출 `predict()` 로 할 수 있습니다. `predict()` 를 하면 recipe 가 새 데이터에 적용된 후, 이가 적합된 모델에 전달됩니다. 


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

종속 변수가 팩터형이기 때문에, `predict()` 의 출력값은 예측 범주: `late` 대 `on_time` 를 반환합니다. 하지만, 각 여객편에 대해 예측 범주 확률을 원한다고 합시다. `predict()` 를 사용할 때 `type = "prob"` 로 명시하거나 `augment()` 를 모델과 테스트 데이터로 with the model plus test data to save them together:


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

Now that we have a tibble with our predicted class probabilities, how will we evaluate the performance of our workflow? We can see from these first few rows that our model predicted these 5 on time flights correctly because the values of `.pred_on_time` are *p* > .50. But we also know that we have 81,455 rows total to predict. We would like to calculate a metric that tells how well our model predicted late arrivals, compared to the true status of our outcome variable, `arr_delay`.

Let's use the area under the [ROC curve](https://bookdown.org/max/FES/measuring-performance.html#class-metrics) as our metric, computed using `roc_curve()` and `roc_auc()` from the [yardstick package](https://yardstick.tidymodels.org/). 

To generate a ROC curve, we need the predicted class probabilities for `late` and `on_time`, which we just calculated in the code chunk above. We can create the ROC curve with these values, using `roc_curve()` and then piping to the `autoplot()` method: 


```r
flights_aug %>% 
  roc_curve(truth = arr_delay, .pred_late) %>% 
  autoplot()
```

<img src="figs/roc-plot-1.svg" width="672" />

Similarly, `roc_auc()` estimates the area under the curve: 


```r
flights_aug %>% 
  roc_auc(truth = arr_delay, .pred_late)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.764
```

Not too bad! We leave it to the reader to test out this workflow [*without*](https://workflows.tidymodels.org/reference/add_formula.html) this recipe. You can use `workflows::add_formula(arr_delay ~ .)` instead of `add_recipe()` (remember to remove the identification variables first!), and see whether our recipe improved our model's ability to predict late arrivals.




## Session information {#session-info}


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
#>  date     2021-10-24                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package      * version date       lib source        
#>  broom        * 0.7.9   2021-07-27 [1] CRAN (R 4.0.2)
#>  dials        * 0.0.10  2021-09-10 [1] CRAN (R 4.0.2)
#>  dplyr        * 1.0.7   2021-06-18 [1] CRAN (R 4.0.2)
#>  ggplot2      * 3.3.5   2021-06-25 [1] CRAN (R 4.0.2)
#>  infer        * 1.0.0   2021-08-13 [1] CRAN (R 4.0.2)
#>  nycflights13 * 1.0.1   2019-09-16 [1] CRAN (R 4.0.2)
#>  parsnip      * 0.1.7   2021-07-21 [1] CRAN (R 4.0.2)
#>  purrr        * 0.3.4   2020-04-17 [1] CRAN (R 4.0.0)
#>  recipes      * 0.1.17  2021-09-27 [1] CRAN (R 4.0.2)
#>  rlang          0.4.12  2021-10-18 [1] CRAN (R 4.0.2)
#>  rsample      * 0.1.0   2021-05-08 [1] CRAN (R 4.0.2)
#>  skimr        * 2.1.3   2021-03-07 [1] CRAN (R 4.0.2)
#>  tibble       * 3.1.5   2021-09-30 [1] CRAN (R 4.0.2)
#>  tidymodels   * 0.1.4   2021-10-01 [1] CRAN (R 4.0.2)
#>  tune         * 0.1.6   2021-07-21 [1] CRAN (R 4.0.2)
#>  workflows    * 0.2.4   2021-10-12 [1] CRAN (R 4.0.2)
#>  yardstick    * 0.0.8   2021-03-28 [1] CRAN (R 4.0.2)
#> 
#> [1] /Library/Frameworks/R.framework/Versions/4.0/Resources/library
```
