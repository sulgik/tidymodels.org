---
title: "recipe 스텝 함수 만들기"
tags: [recipes]
categories: []
type: learn-subsection
weight: 1
description: | 
  Write a new recipe step for data preprocessing.
---





## Introduction

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: modeldata and tidymodels.

There are many existing recipe steps in packages like recipes, themis, textrecipes, and others. A full list of steps in CRAN packages [can be found here](/find/recipes/). However, you might need to define your own preprocessing operations; this article describes how to do that. If you are looking for good examples of existing steps, we suggest looking at the code for [centering](https://github.com/tidymodels/recipes/blob/master/R/center.R) or [PCA](https://github.com/tidymodels/recipes/blob/master/R/pca.R) to start. 

For check operations (e.g. `check_class()`), the process is very similar. Notes on this are available at the end of this article. 

The general process to follow is to:

1. Define a step constructor function.

2. Create the minimal S3 methods for `prep()`, `bake()`, and `print()`.  

3. Optionally add some extra methods to work with other tidymodels packages, such as `tunable()` and `tidy()`. 

As an example, we will create a step for converting data into percentiles. 

## A new step definition

Let's create a step that replaces the value of a variable with its percentile from the training set. The example data we'll use is from the modeldata package:


```r
library(modeldata)
data(biomass)
str(biomass)
#> 'data.frame':	536 obs. of  8 variables:
#>  $ sample  : chr  "Akhrot Shell" "Alabama Oak Wood Waste" "Alder" "Alfalfa" ...
#>  $ dataset : chr  "Training" "Training" "Training" "Training" ...
#>  $ carbon  : num  49.8 49.5 47.8 45.1 46.8 ...
#>  $ hydrogen: num  5.64 5.7 5.8 4.97 5.4 5.75 5.99 5.7 5.5 5.9 ...
#>  $ oxygen  : num  42.9 41.3 46.2 35.6 40.7 ...
#>  $ nitrogen: num  0.41 0.2 0.11 3.3 1 2.04 2.68 1.7 0.8 1.2 ...
#>  $ sulfur  : num  0 0 0.02 0.16 0.02 0.1 0.2 0.2 0 0.1 ...
#>  $ HHV     : num  20 19.2 18.3 18.2 18.4 ...

biomass_tr <- biomass[biomass$dataset == "Training",]
biomass_te <- biomass[biomass$dataset == "Testing",]
```

To illustrate the transformation with the `carbon` variable, note the training set distribution of this variable with a vertical line below for the first value of the test set. 


```r
library(ggplot2)
theme_set(theme_bw())
ggplot(biomass_tr, aes(x = carbon)) + 
  geom_histogram(binwidth = 5, col = "blue", fill = "blue", alpha = .5) + 
  geom_vline(xintercept = biomass_te$carbon[1], lty = 2)
```

<img src="figs/carbon_dist-1.svg" width="100%" />

Based on the training set, 42.1% of the data are less than a value of 46.35. There are some applications where it might be advantageous to represent the predictor values as percentiles rather than their original values. 

Our new step will do this computation for any numeric variables of interest. We will call this new recipe step `step_percentile()`. The code below is designed for illustration and not speed or best practices. We've left out a lot of error trapping that we would want in a real implementation.  

## Create the function

_사용자향(user-facing)_ 함수가 하나 있습니다. `step_percentile()` 라고 부릅시다. 이 함수는 _생성자 함수_ 를 둘러싼 단순한 래퍼인데, 퍼센타일 변환을 정의하는 스텝 객체에 관한 법칙들을 정의합니다. 생성자 함수는 `step_percentile_new()` 라고 부릅시다. 

`step_percentile()` 함수는 당신의 함수와 같은 인수를 입력으로, 새로운 레시피에 추가합니다. `...` 은 사용할 수 있는 변수 selector 를 의미합니다.


```r
step_percentile <- function(
  recipe, 
  ..., 
  role = NA, 
  trained = FALSE, 
  ref_dist = NULL,
  options = list(probs = (0:100)/100, names = TRUE),
  skip = FALSE,
  id = rand_id("percentile")
  ) {

  ## The variable selectors are not immediately evaluated by using
  ##  the `quos()` function in `rlang`. `ellipse_check()` captures 
  ##  the values and also checks to make sure that they are not empty.  
  terms <- ellipse_check(...) 

  add_step(
    recipe, 
    step_percentile_new(
      terms = terms, 
      trained = trained,
      role = role, 
      ref_dist = ref_dist,
      options = options,
      skip = skip,
      id = id
    )
  )
}
```

(`recipe` 에서 `trained` 까지) 첫 네 개의 인수를 항상 위에 나열한 것과 같이 해야 합니다. 몇가지 주목할 사항이 있습니다:

 * `role` 인수는 다음 경우 중 하나에 사용됩니다 1) 새 변수를 생성하고 생성된 변수의 롤들이 프리셋되길 원하는 경우 2) 기존의 변수를 새로운 값들로 대체하는 경우. 우리는 후자를 할 것이고, `role = NA` 을 사용하면 기존의 룰 내용을 유지할 것입니다. 
 * `trained` 는 estimation 스텝이 실행되었을 때 패키지가 설정합니다. 함수 정의의 인수의 기본값을 `FALSE` 로 해야합니다. 
 * `skip` 은 논리형입니다. 레시피가 준비되었을 때마다 각 단계는 훈련된 뒤 적용됩니다. 하지만, `bake()` 호출이 사용될 때 적용되지 않아야 할 단계들이 있습니다. 예를 들어, 한 단계가 "outcomes" 롤이 있는 변수에 적용된다면, 이 데이터는 새로운 샘플에서 사용할 수 없습니다.
* `id` 는 패키지 코드의 단계를 식별할 때 사용할 문자열 입니다. `rand_id()` 는 접두사와 랜덤 문자열을 가진 ID 를 생성할 것입니다.

`approx()` 로 트레이닝 셋으로 부터의 퍼센타일에 기반하여 새로운 데이터 포인트의 퍼센타일을 추정할 수 있습니다. 우리 `step_percentile` 는 `ref_dist` 객체를 포함하여 이러한 퍼센타일을 저장하여 (`prep()` 을 하여 트레이닝셋으로부터 미리 계산하여) `bake()` 에서 나중에 사용하게 합니다.

`stats::quantile()` 을 사용하여 그리드를 계산할 것입니다. 하지만, 이 그리드의 granularity 를 조정하고 싶기 때문에, `options` 인수가 계산이 어떻게 수행될 것인지를 정의하는데 사용될 것입니다. `step_percentile()` 의 인수가 아닌 전달된 옵션이 `stats::quantile()` 로 전달되도록 ellipses (다른 말로 `...`) 를 사용할 수 있습니다. 하지만, 옵션으로 분리된 리스트 객체를 만들고 함수 내에서 사용하기를 추천하는데, `...` 은 변수 선택을 정의하는 데 이미 사용되기 때문입니다.

단계에 _메인 인수들_ 이 있다면, 고려하는 것이 중요합니다. 예를 들어, `step_ns()` 같은 spline-관련 스텝들에 대해, 사용자들은 spline 에서 자유도 인수를 조정하길 원합니다 (e.g. `splines::ns(x, df)`). 사용자들에게 `df` 를 `options` 인수에 추가하는 것 대신:

* 중요한 인수들이 스텝 함수의 메인 인수들로 합니다. 

* [인수 명명 컨벤션](https://tidymodels.github.io/model-implementation-principles/standardized-argument-names.html)을 따른다. 가능한한 은어를 피하고 공통 인수 이름을 따릅니다.  

이 원칙을 따르면 이점이 있습니다. (아래 참고). 

## 새 객체 초기화하기

이제, 생성자 함수를 생성할 수 있습니다.

함수 케스케이드는: 

```
step_percentile() calls recipes::add_step()
└──> recipes::add_step() calls step_percentile_new()
    └──> step_percentile_new() calls recipes::step()
```

`step()` 은 레시피를 위한 일반 생성자인데, 결과 스텝 객체는 적절한 S3 클래스 구조를 가진 리스트입니다. `subclass = "percentile"` 을 하면, 새 객체의 클래스를 `"step_percentile"` 로 설정합니다.


```r
step_percentile_new <- 
  function(terms, role, trained, ref_dist, options, skip, id) {
    step(
      subclass = "percentile", 
      terms = terms,
      role = role,
      trained = trained,
      ref_dist = ref_dist,
      options = options,
      skip = skip,
      id = id
    )
  }
```

이 생성자 함수는 기본 인수값이 없어야 합니다. 기본값은 이용자향 스텝 객체에서 설정되어야 햡니다. 

## `prep` 메소드 생성하기

당신의 스텝의 클래스를 위한 새로운 `prep()` 메소드를 생성해야 합니다. 메소드가 가져야 할 세 가지 인수는 다음과 같습니다:

```r
function(x, training, info = NULL)
```

where

 * `x` will be the `step_percentile` object,
 * `training` will be a _tibble_ that has the training set data, and
 * `info` will also be a tibble that has information on the current set of data available. This information is updated as each step is evaluated by its specific `prep()` method so it may not have the variables from the original data. The columns in this tibble are `variable` (the variable name), `type` (currently either "numeric" or "nominal"), `role` (defining the variable's role), and `source` (either "original" or "derived" depending on where it originated).

You can define other arguments as well. 

The first thing that you might want to do in the `prep()` function is to translate the specification listed in the `terms` argument to column names in the current data. There is a function called `recipes_eval_select()` that can be used to obtain this. 

{{% warning %}} The `recipes_eval_select()` function is not one you interact with as a typical recipes user, but it is helpful if you develop your own custom recipe steps. {{%/ warning %}}


```r
prep.step_percentile <- function(x, training, info = NULL, ...) {
  col_names <- recipes_eval_select(x$terms, training, info) 
  # TODO finish the rest of the function
}
```

After this function call, it is a good idea to check that the selected columns have the appropriate type (e.g. numeric for this example). See `recipes::check_type()` to do this for basic types. 

Once we have this, we can save the approximation grid. For the grid, we will use a helper function that enables us to run `rlang::exec()` to splice in any extra arguments contained in the `options` list to the call to `quantile()`: 


```r
get_train_pctl <- function(x, args = NULL) {
  res <- rlang::exec("quantile", x = x, !!!args)
  # Remove duplicate percentile values
  res[!duplicated(res)]
}

# For example:
get_train_pctl(biomass_tr$carbon, list(probs = 0:1))
#>   0% 100% 
#> 14.6 97.2
get_train_pctl(biomass_tr$carbon)
#>   0%  25%  50%  75% 100% 
#> 14.6 44.7 47.1 49.7 97.2
```

Now, the `prep()` method can be created: 


```r
prep.step_percentile <- function(x, training, info = NULL, ...) {
  col_names <- recipes_eval_select(x$terms, training, info)
  ## You can add error trapping for non-numeric data here and so on. 
  
  ## We'll use the names later so make sure they are available
  if (x$options$names == FALSE) {
    rlang::abort("`names` should be set to TRUE")
  }
  
  if (!any(names(x$options) == "probs")) {
    x$options$probs <- (0:100)/100
  } else {
    x$options$probs <- sort(unique(x$options$probs))
  }
  
  # Compute percentile grid
  ref_dist <- purrr::map(training[, col_names],  get_train_pctl, args = x$options)

  ## Use the constructor function to return the updated object. 
  ## Note that `trained` is now set to TRUE
  
  step_percentile_new(
    terms = x$terms, 
    trained = TRUE,
    role = x$role, 
    ref_dist = ref_dist,
    options = x$options,
    skip = x$skip,
    id = x$id
  )
}
```

We suggest favoring `rlang::abort()` and `rlang::warn()` over `stop()` and `warning()`. The former can be used for better traceback results.


## Create the `bake` method

Remember that the `prep()` function does not _apply_ the step to the data; it only estimates any required values such as `ref_dist`. We will need to create a new method for our `step_percentile()` class. The minimum arguments for this are

```r
function(object, new_data, ...)
```

where `object` is the updated step function that has been through the corresponding `prep()` code and `new_data` is a tibble of data to be processed. 

Here is the code to convert the new data to percentiles. The input data (`x` below) comes in as a numeric vector and the output is a vector of approximate percentiles: 


```r
pctl_by_approx <- function(x, ref) {
  # In case duplicates were removed, get the percentiles from
  # the names of the reference object
  grid <- as.numeric(gsub("%$", "", names(ref))) 
  approx(x = ref, y = grid, xout = x)$y/100
}
```

These computations are done column-wise using `purrr::map2_dfc()` to modify the new data in-place:


```r
bake.step_percentile <- function(object, new_data, ...) {
  ## For illustration (and not speed), we will loop through the affected variables
  ## and do the computations
  vars <- names(object$ref_dist)
  
  new_data[, vars] <-
    purrr::map2_dfc(new_data[, vars], object$ref_dist, pctl_by_approx)
  
  ## Always convert to tibbles on the way out
  tibble::as_tibble(new_data)
}
```

{{% note %}} You need to import `recipes::prep()` and `recipes::bake()` to create your own step function in a package. {{%/ note %}}

## Run the example

Let's use the example data to make sure that it works: 


```r
rec_obj <- 
  recipe(HHV ~ ., data = biomass_tr) %>%
  step_percentile(ends_with("gen")) %>%
  prep(training = biomass_tr)

biomass_te %>% select(ends_with("gen")) %>% slice(1:2)
#>   hydrogen oxygen nitrogen
#> 1     5.67   47.2     0.30
#> 2     5.50   48.1     2.85
bake(rec_obj, biomass_te %>% slice(1:2), ends_with("gen"))
#> # A tibble: 2 × 3
#>   hydrogen oxygen nitrogen
#>      <dbl>  <dbl>    <dbl>
#> 1     0.45  0.903    0.21 
#> 2     0.38  0.922    0.928

# Checking to get approximate result: 
mean(biomass_tr$hydrogen <= biomass_te$hydrogen[1])
#> [1] 0.452
mean(biomass_tr$oxygen   <= biomass_te$oxygen[1])
#> [1] 0.901
```

The plot below shows how the original hydrogen percentiles line up with the estimated values:


```r
hydrogen_values <- 
  bake(rec_obj, biomass_te, hydrogen) %>% 
  bind_cols(biomass_te %>% select(original = hydrogen))

ggplot(biomass_tr, aes(x = hydrogen)) + 
  # Plot the empirical distribution function of the 
  # hydrogen training set values as a black line
  stat_ecdf() + 
  # Overlay the estimated percentiles for the new data: 
  geom_point(data = hydrogen_values, 
             aes(x = original, y = hydrogen), 
             col = "red", alpha = .5, cex = 2) + 
  labs(x = "New Hydrogen Values", y = "Percentile Based on Training Set")
```

<img src="figs/cdf_plot-1.svg" width="672" />

These line up very nicely! 

## Custom check operations 

The process here is exactly the same as steps; the internal functions have a similar naming convention: 

 * `add_check()` instead of `add_step()`
 * `check()` instead of `step()`, and so on. 
 
It is strongly recommended that:
 
 1. The operations start with `check_` (i.e. `check_range()` and `check_range_new()`)
 1. The check uses `rlang::abort(paste0(...))` when the conditions are not met
 1. The original data are returned (unaltered) by the check when the conditions are satisfied. 

## Other step methods

There are a few other S3 methods that can be created for your step function. They are not required unless you plan on using your step in the broader tidymodels package set. 

### A print method

If you don't add a print method for `step_percentile`, it will still print but it will be printed as a list of (potentially large) objects and look a bit ugly. The recipes package contains a helper function called `printer()` that should be useful in most cases. We are using it here for the custom print method for `step_percentile`. It requires the original terms specification and the column names this specification is evaluated to by `prep()`. For the former, our step object is structured so that the list object `ref_dist` has the names of the selected variables: 


```r
print.step_percentile <-
  function(x, width = max(20, options()$width - 35), ...) {
    cat("Percentile transformation on ", sep = "")
    printer(
      # Names before prep (could be selectors)
      untr_obj = x$terms,
      # Names after prep:
      tr_obj = names(x$ref_dist),
      # Has it been prepped? 
      trained = x$trained,
      # An estimate of how many characters to print on a line: 
      width = width
    )
    invisible(x)
  }

# Results before `prep()`:
recipe(HHV ~ ., data = biomass_tr) %>%
  step_percentile(ends_with("gen"))
#> Recipe
#> 
#> Inputs:
#> 
#>       role #variables
#>    outcome          1
#>  predictor          7
#> 
#> Operations:
#> 
#> Percentile transformation on ends_with("gen")

# Results after `prep()`: 
rec_obj
#> Recipe
#> 
#> Inputs:
#> 
#>       role #variables
#>    outcome          1
#>  predictor          7
#> 
#> Training data contained 456 data points and no missing data.
#> 
#> Operations:
#> 
#> Percentile transformation on hydrogen, oxygen, nitrogen [trained]
```
 
### Methods for declaring required packages

Some recipe steps use functions from other packages. When this is the case, the `step_*()` function should check to see if the package is installed. The function `recipes::recipes_pkg_check()` will do this. For example: 

```
> recipes::recipes_pkg_check("some_package")
1 package is needed for this step and is not installed. (some_package). Start 
a clean R session then run: install.packages("some_package")
```

There is an S3 method that can be used to declare what packages should be loaded when using the step. For a hypothetical step that relies on the `hypothetical` package, this might look like: 


```r
required_pkgs.step_hypothetical <- function(x, ...) {
  c("hypothetical", "myrecipespkg")
}
```

In this example, `myrecipespkg` is the package where the step resides (if it is in a package).

The reason to declare what packages should be loaded is parallel processing. When parallel worker processes are created, there is heterogeneity across technologies regarding which packages are loaded. Multicore methods on macOS and Linux load all of the packages that were loaded in the main R process. However, parallel processing using psock clusters have no additional packages loaded. If the home package for a recipe step is not loaded in the worker processes, the `prep()` methods cannot be found and an error occurs. 

If this S3 method is used for your step, you can rely on this for checking the installation: 
 

```r
recipes::recipes_pkg_check(required_pkgs.step_hypothetical())
```

If you'd like an example of this in a package, please take a look at the [embed](https://github.com/tidymodels/embed/) or [themis](https://github.com/tidymodels/themis/) package.

### A tidy method

The `broom::tidy()` method is a means to return information about the step in a usable format. For our step, it would be helpful to know the reference values. 

When the recipe has been prepped, those data are in the list `ref_dist`. A small function can be used to reformat that data into a tibble. It is customary to return the main values as `value`:


```r
format_pctl <- function(x) {
  tibble::tibble(
    value = unname(x),
    percentile = as.numeric(gsub("%$", "", names(x))) 
  )
}

# For example: 
pctl_step_object <- rec_obj$steps[[1]]
pctl_step_object
#> Percentile transformation on hydrogen, oxygen, nitrogen [trained]
format_pctl(pctl_step_object$ref_dist[["hydrogen"]])
#> # A tibble: 87 × 2
#>    value percentile
#>    <dbl>      <dbl>
#>  1 0.03           0
#>  2 0.934          1
#>  3 1.60           2
#>  4 2.07           3
#>  5 2.45           4
#>  6 2.74           5
#>  7 3.15           6
#>  8 3.49           7
#>  9 3.71           8
#> 10 3.99           9
#> # … with 77 more rows
```

The tidy method could return these values for each selected column. Before `prep()`, missing values can be used as placeholders. 


```r
tidy.step_percentile <- function(x, ...) {
  if (is_trained(x)) {
    res <- map_dfr(x$ref_dist, format_pctl, .id = "term")
  }
  else {
    term_names <- sel2char(x$terms)
    res <-
      tibble(
        terms = term_names,
        value = rlang::na_dbl,
        percentile = rlang::na_dbl
      )
  }
  # Always return the step id: 
  res$id <- x$id
  res
}

tidy(rec_obj, number = 1)
#> # A tibble: 274 × 4
#>    term     value percentile id              
#>    <chr>    <dbl>      <dbl> <chr>           
#>  1 hydrogen 0.03           0 percentile_qi6LP
#>  2 hydrogen 0.934          1 percentile_qi6LP
#>  3 hydrogen 1.60           2 percentile_qi6LP
#>  4 hydrogen 2.07           3 percentile_qi6LP
#>  5 hydrogen 2.45           4 percentile_qi6LP
#>  6 hydrogen 2.74           5 percentile_qi6LP
#>  7 hydrogen 3.15           6 percentile_qi6LP
#>  8 hydrogen 3.49           7 percentile_qi6LP
#>  9 hydrogen 3.71           8 percentile_qi6LP
#> 10 hydrogen 3.99           9 percentile_qi6LP
#> # … with 264 more rows
```

### Methods for tuning parameters

The tune package can be used to find reasonable values of step arguments by model tuning. There are some S3 methods that are useful to define for your step. The percentile example doesn't really have any tunable parameters, so we will demonstrate using `step_poly()`, which returns a polynomial expansion of selected columns. Its function definition has the arguments: 


```r
args(step_poly)
#> function (recipe, ..., role = "predictor", trained = FALSE, objects = NULL, 
#>     degree = 2, options = list(), skip = FALSE, id = rand_id("poly")) 
#> NULL
```

The argument `degree` is tunable.

To work with tune it is _helpful_ (but not required) to use an S3 method called `tunable()` to define which arguments should be tuned and how values of those arguments should be generated. 

`tunable()` takes the step object as its argument and returns a tibble with columns: 

* `name`: The name of the argument. 

* `call_info`: A list that describes how to call a function that returns a dials parameter object. 

* `source`: A character string that indicates where the tuning value comes from (i.e., a model, a recipe etc.). Here, it is just `"recipe"`. 

* `component`: A character string with more information about the source. For recipes, this is just the name of the step (e.g. `"step_poly"`). 

* `component_id`: A character string to indicate where a unique identifier is for the object. For recipes, this is just the `id` value of the step object.  

The main piece of information that requires some detail is `call_info`. This is a list column in the tibble. Each element of the list is a list that describes the package and function that can be used to create a dials parameter object. 

For example, for a nearest-neighbors `neighbors` parameter, this value is just: 


```r
info <- list(pkg = "dials", fun = "neighbors")

# FYI: how it is used under-the-hood: 
new_param_call <- rlang::call2(.fn = info$fun, .ns = info$pkg)
rlang::eval_tidy(new_param_call)
#> # Nearest Neighbors (quantitative)
#> Range: [1, 10]
```

For `step_poly()`, a dials object is needed that returns an integer that is the number of new columns to create. It turns out that there are a few different types of tuning parameters related to degree: 

```r
> lsf.str("package:dials", pattern = "degree")
degree : function (range = c(1, 3), trans = NULL)  
degree_int : function (range = c(1L, 3L), trans = NULL)  
prod_degree : function (range = c(1L, 2L), trans = NULL)  
spline_degree : function (range = c(3L, 10L), trans = NULL)  
```

Looking at the `range` values, some return doubles and others return integers. For our problem, `degree_int()` would be a good choice. 

For `step_poly()` the `tunable()` S3 method could be: 


```r
tunable.step_poly <- function (x, ...) {
  tibble::tibble(
    name = c("degree"),
    call_info = list(list(pkg = "dials", fun = "degree_int")),
    source = "recipe",
    component = "step_poly",
    component_id = x$id
  )
}
```


## Session information


```
#> ─ Session info  👧🏼  ⛱️  🇸🇷   ────────────────────────────────────────
#>  hash: girl: medium-light skin tone, umbrella on ground, flag: Suriname
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
#>  date     2022-01-02
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
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
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
 
 
