---
title: "broom tidier 메소드 만들기"
tags: [broom]
categories: []
type: learn-subsection
weight: 5
description: | 
  새로운 모델 객체에 해당하는 tidy(), glance(), augment() 메소드를 작성한다.
---
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />





## 들어가기

To use the code in this article, you have to install the following packages: generics, tidymodels, tidyverse, and usethis.

broom 패키지의 도구들을 이용하면 타이디한 `tibble()` 에 있는 모델들에 대한 핵심 정보를 요약할 수 있습니다. 이 패키지에는 모델 객체를 다루기 쉽게 만들어 주는 동사, 혹은 "tidiers" 세 개를 제공합니다. 

* `tidy()` 는 모델 컴포넌트들에 대한 정보를 요약합니다
* `glance()` 는 전체 모델에 대한 정보를 보고합니다
* `augment()` 는 관측값들에 대한 정보를 데이터셋에 추가합니다

위의 세 동사들은 모두 _제너릭_ 입니다. 왜냐하면, 이 동사들은 주어진 모델 객체를 타이디하게 하는 프로시져를 정의하지 않는 대신, 특정 모델 객체 관련된 _메서드_ (특별한 유형의 모델 객체를 타이디하게 하기 위해 구현한) 로 리디렉트하기 때문입니다. broom 패키지에는 base R 의 stats 패키지를 포함하여 100 개가 넘는 모델링 패키지에 있는 모델 객체에 적용할 수 있는 메소드들이 있습니다. 하지만, 관리상의 이유로 broom 패키지 저자들은 새로운 메소드 요청이 broom 이 아닌 부모 패키지에 지시될 것을 요구합니다. (즉 해당 모델 객체를 제공한 패키지) 새로운 메소드는 요청자가 모델소유 패키지의 관리자에게 부모 패키지의 tidier 메소드들을 구현해 달라고 요청한 경우에만 broom 에 일반적으로 만들어질 것입니다.

외부 tidier 메소드들을 가능한한 가장 힘들지 않게 구현하려고 합니다. 일반적인 과정은 다음과 같습니다:

* tidier 제네릭을 다시 익스포트하기
* tidy 메소드를 구현하기
* 새 메소드를 문서화하기

이번 문서에서는 위에서 언급한 각 단계를 자세히 따라가면서 예를 살펴보고 도움이 되는 함수들을 볼 것입니다.

##  tidier 제네릭을 다시 익스포트하기

첫번째 단계는 `tidy()`, `glance()`, `augment()` 에 대한 제네릭 함수들을 다시 익스포트 하는 것입니다. `broom` 에서 직접할 수도 있지만, `generics` 으로 부르는 더 가벼운 의존성을 가진 다른 방법을 제시합니다.

우선 `Imports` 에 [generics](https://github.com/r-lib/generics) 패키지를 추가해야 합니다. [usethis](https://github.com/r-lib/usethis) 패키지를 사용할 것을 추천합니다:


```r
usethis::use_package("generics", "Imports")
```

다음으로, 적절한 타이디 메소드들을 다시 익스포트 해야합니다. 예를 들어 `glance()` 메소드를 다시 구현하려고 한다면, 당신 패키지의 `/R`  폴더 내부 어딘가에 다음을 추가하여 `glance()` 제네릭을 다시 익스포트할 수 있습니다:


```r
#' @importFrom generics glance
#' @export
generics::glance
```

특정 모델의 이러한 메소드들을 정의하는 것이 적절하지 않은 경우가 있습니다. 이런 경우에는 적절한 메소드만 구현하세요.

{{% warning %}} Please do not define `tidy()`, `glance()`, or `augment()` generics in your package. This will result in namespace conflicts whenever your package is used along other packages that also export tidying methods. {{%/ warning %}}

## 타이디 메소드를 구현하기

위 단계에서 익스포트한 제네릭 각각에 대한 타이디 메소드들을 구현해야 합니다. `tidy()`, `glance()`, and `augment()` 각각에 대해, 큰 그림, 예시, 유용한 자원들을 살펴볼 것입니다.

여기서 베이스 R 데이터셋 `trees` 를 사용할 것인데, 이 데이터셋의 나무 둘레 (Girth, 인치단위), 키 (Height, 피트단위), 부피 (Volume, 큐빅피트단위) 으로 베이스 R `lm()` 함수를 사용하여 선형모형을 예로 적합할 것입니다. 


```r
# load in the trees dataset
data(trees)

# take a look!
str(trees)
#> 'data.frame':	31 obs. of  3 variables:
#>  $ Girth : num  8.3 8.6 8.8 10.5 10.7 10.8 11 11 11.1 11.2 ...
#>  $ Height: num  70 65 63 72 81 83 66 75 80 75 ...
#>  $ Volume: num  10.3 10.3 10.2 16.4 18.8 19.7 15.6 18.2 22.6 19.9 ...

# fit the timber volume as a function of girth and height
trees_model <- lm(Volume ~ Girth + Height, data = trees)
```

`trees_model` 적합결과의 `summary()` 를 살펴봅시다.


```r
summary(trees_model)
#> 
#> Call:
#> lm(formula = Volume ~ Girth + Height, data = trees)
#> 
#> Residuals:
#>    Min     1Q Median     3Q    Max 
#> -6.406 -2.649 -0.288  2.200  8.485 
#> 
#> Coefficients:
#>             Estimate Std. Error t value Pr(>|t|)    
#> (Intercept)  -57.988      8.638   -6.71  2.7e-07 ***
#> Girth          4.708      0.264   17.82  < 2e-16 ***
#> Height         0.339      0.130    2.61    0.014 *  
#> ---
#> Signif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1
#> 
#> Residual standard error: 3.88 on 28 degrees of freedom
#> Multiple R-squared:  0.948,	Adjusted R-squared:  0.944 
#> F-statistic:  255 on 2 and 28 DF,  p-value: <2e-16
```

이 결과물에는 잔차에 요약 통계량 (`augment()` 출력에 전체 목록이 있음) 과 모형 계수 (이 경우 `tidy()` 출력을 완성함), RSE, `\(R^2\)` 같은 모델 레벨의 요약 (`glance()` 출력이 보충함) 이 나옵니다. 

### `tidy()` 메소드 구현하기

`tidy(x, ...)` 메소드는 티블을 반환하는데, 이 티블의 각 행은 모델 구성요소에 대한 정보를 포함합니다. `x` 인풋은 모델 객체이고 점들 (`...`) 은 당신의 메소드 내부의 호출에 추가적인 정보를 제공하는 선택적 인수입니다. 새로운 `tidy()` 메소드는 추가적인 인수들을 취할 수 있지만 제네릭 함수와 호환되어야 하기 때문에 `x` 와 `...` 인수들을 포함 __해야합니다__. (현재 허용되는 추가 인수들의 목록은 [이 장의 마지막](#glossary)에 정리되어 있습니다.) 모델 구성요소들의 예로는 회귀 계수 (회귀 모델의 경우) 클러스터 (분류/클러스터 모델들) 등입니다. 이러한 `tidy()` 메소드들은 모델 세부사항들을 살펴보고 커스텀 모델 시각화를 생성하는 데에 유용합니다.

목재 부피에 관한 선형 모형 예로 돌아가서, 모델 구성요소에 관한 정보를 추출하려고 합니다. 이 예에서, 구성요소는 회귀 계수들입니다. 모델 객체와 이에 대한 `summary()` 를 살펴보면 다음과 같이 회귀 계수를 추출할 수 있음을 알 수 있을 것입니다:


```r
summary(trees_model)$coefficients
#>             Estimate Std. Error t value Pr(>|t|)
#> (Intercept)  -57.988      8.638   -6.71 2.75e-07
#> Girth          4.708      0.264   17.82 8.22e-17
#> Height         0.339      0.130    2.61 1.45e-02
```

이 객체는 테이블 형태로 모델 계수를 포함하는데, 각 행에서 어떤 계수가 기술되는지에 관한 정보가 행 이름에 나와있습니다. 행 이름이 하나의 열에 포함된 티블로 변환시키려면 다음과 같이 작성하면 됩니다:


```r
trees_model_tidy <- summary(trees_model)$coefficients %>% 
  as_tibble(rownames = "term")

trees_model_tidy
#> # A tibble: 3 x 5
#>   term        Estimate `Std. Error` `t value` `Pr(>|t|)`
#>   <chr>          <dbl>        <dbl>     <dbl>      <dbl>
#> 1 (Intercept)  -58.0          8.64      -6.71   2.75e- 7
#> 2 Girth          4.71         0.264     17.8    8.22e-17
#> 3 Height         0.339        0.130      2.61   1.45e- 2
```

broom 패키지는 계수들을 기술하는 공통된 열 이름을 표준화합니다. 이 경우, 열 이름은 다음과 같습니다:


```r
colnames(trees_model_tidy) <- c("term", "estimate", "std.error", "statistic", "p.value")
```

`tidy()` 메소드 출력으로 인정되는 열 이름들이 포함된 용어집(glossary)은 [이 문서의 마지막](#glossary)에 있습니다. 쉬운 법칙으로, `tidy()` 메소드가 제공할 열이름은 모두 소문자이어야 하고, 알파벳, 숫자, 점 외에는 포함해서는 안됩니다 (비록 예외가 많이 있습니다).

마지막으로, 대부분 `tidy()` 메소드에는 모델에 기반한 각 구성요소에 대한 신뢰/credible 구간을 포함됩니다. 우리 예에서, `confint()` 함수를 사용하여 `lm()` 이 제공하는 모델 객체로 부터 신뢰 구간을 계산할 수 있습니다.


```r
confint(trees_model)
#>                2.5 %  97.5 %
#> (Intercept) -75.6823 -40.293
#> Girth         4.1668   5.249
#> Height        0.0726   0.606
```

앞에서 살펴본 것들을 고려하여, `lm()` 의 적절한 `tidy()` 메소드는 예를 들어 다음과 같이 할 수 있습니다:


```r
tidy.lm <- function(x, conf.int = FALSE, conf.level = 0.95, ...) {
  
  result <- summary(x)$coefficients %>%
    tibble::as_tibble(rownames = "term") %>%
    dplyr::rename(estimate = Estimate,
                  std.error = `Std. Error`,
                  statistic = `t value`,
                  p.value = `Pr(>|t|)`)
  
  if (conf.int) {
    ci <- confint(x, level = conf.level)
    result <- dplyr::left_join(result, ci, by = "term")
  }
  
  result
}
```

{{% note %}}  If you're interested, the actual `tidy.lm()` source can be found [here](https://github.com/tidymodels/broom/blob/master/R/stats-lm-tidiers.R)! It's not too different from the version above except for some argument checking and additional columns. {{%/ note %}}

이렇게 익스포트된 방법으로 `fit` 이 `lm()` 의 출력인, `tidy(fit)` 가 호출되면, `tidy()` 제네릭은 위의 `tidy.lm()` 함수 호출로 "리디렉션" 합니다.

`tidy()` 메소드를 작성할 때 명심해야할 것들입니다:

* 어떤 모델은 구성요소들이 다른 유형들로 이루어져 있습니다. 예를 들어, mixed model 에서는, fixed 효과와 랜덤 효과들과 연관된 다른 정보들이 있습니다. 이 정보는 같은 해석을 가지지 않으므로, fixed 효과와 random 효과를 같은 테이블에 정리하는 것은 이상합니다. 이와 같은 경우 사용자에게 어떤 종류의 정보를 원하는지를 명시하도록 하는 인수를 추가해야 합니다. 예를 들어, 다음과 같은 선상에서 인터페이스를 구현할 수 있습니다:


```r
model <- mixed_model(...)
tidy(model, effects = "fixed")
tidy(model, effects = "random")
```

* 모델 객체와 이 객체의 `summary()` 에서 결측치들은 어떻게 인코딩 되는가? 연관된 모델 구성요소들이 없거나 rank deficient 해도 해당 행을 꼭 포함하세요.
* 각 요소들의 요약에 포함되기를 기대되는 다른 measure 가 있는가? 다음은 `tidy()` 메소드의 공통적인 인수들입니다:
  - `conf.int`: A logical indicating whether or not to calculate confidence/credible intervals 를 계산해야할지 말지를 가리키는 논리형. 기본값은 `FALSE` 가 되어야함.
  - `conf.level`: `conf.int = TRUE` 일 때 사용할 신뢰 수준. 일반적인 기본값은 `.95`.
  - `exponentiate`: 모델 term 들을 exponential 스케일로 나타낼지 말지를 가리키는 논리형 (로지스틱 회귀에서 흔함).

### `glance()` 메소드 구현하기

`glance()` 은 모델 레벨 요약값 (예. goodness of fit 측정값과 관련된 통계량) 을 제공하는 1행 티블을 반환합니다. 이는 모델을 잘못 만든 것을 체크하거나 많은 모델을 비교하는데 유용합니다. 여기서도, `x` 인풋은 모델 객체이고 `...` 은 메소드 내부의 모든 호출에 추가 정보를 제공하는 선택적 인자입니다. 새로운 `glance()` 메소드는 `x` 와 `...` 인수들을 포함_해야하고_, 추가적인 인수들을 입력으로 할 수 있습니다. (현재 허용되는 추가 인수들의 목록은 [이 장의 마지막](#glossary)에 정리되어 있습니다.)

`trees_model` 예로 돌아와서, 다음의 코드로 `\(R^2\)` 값을 추출할 수 있을 것입니다:


```r
summary(trees_model)$r.squared
#> [1] 0.948
```

같은 방법으로, adjusted `\(R^2\)` 는 다음과 같이 합니다:


```r
summary(trees_model)$adj.r.squared
#> [1] 0.944
```

Unfortunately, for many model objects, the extraction of model-level information is largely a manual process. You will likely need to build a `tibble()` element-by-element by subsetting the `summary()` object repeatedly. The `with()` function, however, can help make this process a bit less tedious by evaluating expressions inside of the `summary(trees_model)` environment. To grab those those same two model elements from above using `with()`:


```r
with(summary(trees_model),
     tibble::tibble(r.squared = r.squared,
                    adj.r.squared = adj.r.squared))
#> # A tibble: 1 x 2
#>   r.squared adj.r.squared
#>       <dbl>         <dbl>
#> 1     0.948         0.944
```

A reasonable `glance()` method for `lm()`, then, might look something like:


```r
glance.lm <- function(x, ...) {
  with(
    summary(x),
    tibble::tibble(
      r.squared = r.squared,
      adj.r.squared = adj.r.squared,
      sigma = sigma,
      statistic = fstatistic["value"],
      p.value = pf(
        fstatistic["value"],
        fstatistic["numdf"],
        fstatistic["dendf"],
        lower.tail = FALSE
      ),
      df = fstatistic["numdf"],
      logLik = as.numeric(stats::logLik(x)),
      AIC = stats::AIC(x),
      BIC = stats::BIC(x),
      deviance = stats::deviance(x),
      df.residual = df.residual(x),
      nobs = stats::nobs(x)
    )
  )
}
```

{{% note %}} This is the actual definition of `glance.lm()` provided by broom! {{%/ note %}}

Some things to keep in mind while writing `glance()` methods:
* Output should not include the name of the modeling function or any arguments given to the modeling function.
* In some cases, you may wish to provide model-level diagnostics not returned by the original object. For example, the above `glance.lm()` calculates `AIC` and `BIC` from the model fit. If these are easy to compute, feel free to add them. However, tidier methods are generally not an appropriate place to implement complex or time consuming calculations.
* The `glance` method should always return the same columns in the same order when given an object of a given model class. If a summary metric (such as `AIC`) is not defined in certain circumstances, use `NA`.

### `augment()` 메소드 구현하기

`augment()` 메소드는 fitted values, 잔차, 클러스터 할당과 같은 정보를 포함하는 데이터셋에 열들을 추가합니다. 데이터셋에 추가되는 모든 열들은 `.` prefix 를 가지는데, 기존의 열들이 덮어써지는 것을 막아주기 위함입니다. (Currently acceptable column names are given in [the glossary](#glossary)). `x` 와 `...` 인수들은 위에 기술한 두 함수들에서의 의미와 같습니다. `argument` 메소드는 선택적으로 관측값레벨 정보가 추가될 `data.frame` (혹은 `tibble`) 인 `data` 인수를 입력으로, `data` 와 같은 행수를 가진 `tibble` 객체를 반환합니다. 많은 `argument()` 메소드들은 `newdata` 인수를 입력으로하며, 모델이 데이터를 "보지" 않았다는 가정을 제외하고 `data` 인수와 같은 컨벤션을 따릅니다. 결과적으로 `newdata` 인수는 `data` 의 반응변수 열을 포함할 필요가 없습니다. `data` 나 `newdata` 중 어느 하나만 제공되어야 합니다. `argument()` 메소드에 허용되는 전체 인수 목록은 [이번 장의 마지막](#glossary)에 있습니다.

`data` 인수가 명시되지 않으면 `augment()` 는 원 데이터를 모델 객체에서 최대한 재구축하려고 노력할 것입니다. 이런 것이 항상 가능한 것은 아니고, 모델에서 사용되지 않는 열들을 복원하는 것은 가능하지 않을 수 있습니다.

이를 명심하고, 우리 `trees_model` 예를 돌아가 봅니다. `trees_model` 객체 내부의 `model` 요소를 사용하면 원 데이터를 복원할 수 있습니다:


```r
trees_model$model
#>    Volume Girth Height
#> 1    10.3   8.3     70
#> 2    10.3   8.6     65
#> 3    10.2   8.8     63
#> 4    16.4  10.5     72
#> 5    18.8  10.7     81
#> 6    19.7  10.8     83
#> 7    15.6  11.0     66
#> 8    18.2  11.0     75
#> 9    22.6  11.1     80
#> 10   19.9  11.2     75
#> 11   24.2  11.3     79
#> 12   21.0  11.4     76
#> 13   21.4  11.4     76
#> 14   21.3  11.7     69
#> 15   19.1  12.0     75
#> 16   22.2  12.9     74
#> 17   33.8  12.9     85
#> 18   27.4  13.3     86
#> 19   25.7  13.7     71
#> 20   24.9  13.8     64
#> 21   34.5  14.0     78
#> 22   31.7  14.2     80
#> 23   36.3  14.5     74
#> 24   38.3  16.0     72
#> 25   42.6  16.3     77
#> 26   55.4  17.3     81
#> 27   55.7  17.5     82
#> 28   58.3  17.9     80
#> 29   51.5  18.0     80
#> 30   51.0  18.0     80
#> 31   77.0  20.6     87
```

Similarly, the fitted values and residuals can be accessed with the following code:


```r
head(trees_model$fitted.values)
#>     1     2     3     4     5     6 
#>  4.84  4.55  4.82 15.87 19.87 21.02
head(trees_model$residuals)
#>      1      2      3      4      5      6 
#>  5.462  5.746  5.383  0.526 -1.069 -1.318
```

As with `glance()` methods, it's fine (and encouraged!) to include common metrics associated with observations if they are not computationally intensive to compute. A common metric associated with linear models, for example, is the standard error of fitted values:


```r
se.fit <- predict(trees_model, newdata = trees, se.fit = TRUE)$se.fit %>%
  unname()

head(se.fit)
#> [1] 1.321 1.489 1.633 0.944 1.348 1.532
```

Thus, a reasonable `augment()` method for `lm` might look something like this:


```r
augment.lm <- function(x, data = x$model, newdata = NULL, ...) {
  if (is.null(newdata)) {
    dplyr::bind_cols(tibble::as_tibble(data),
                     tibble::tibble(.fitted = x$fitted.values,
                                    .se.fit = predict(x, 
                                                      newdata = data, 
                                                      se.fit = TRUE)$se.fit,
                                   .resid =  x$residuals))
  } else {
    predictions <- predict(x, newdata = newdata, se.fit = TRUE)
    dplyr::bind_cols(tibble::as_tibble(newdata),
                     tibble::tibble(.fitted = predictions$fit,
                                    .se.fit = predictions$se.fit))
  }
}
```

Some other things to keep in mind while writing `augment()` methods:
* The `newdata` argument should default to `NULL`. Users should only ever specify one of `data` or `newdata`. Providing both `data` and `newdata` should result in an error. The `newdata` argument should accept both `data.frame`s and `tibble`s.
* Data given to the `data` argument must have both the original predictors and the original response. Data given to the `newdata` argument only needs to have the original predictors. This is important because there may be important information associated with training data that is not associated with test data. This means that the `original_data` object in `augment(model, data = original_data)` should provide `.fitted` and `.resid` columns (in most cases), whereas `test_data` in `augment(model, data = test_data)` only needs a `.fitted` column, even if the response is present in `test_data`.
* If the `data` or `newdata` is specified as a `data.frame` with rownames, `augment` should return them in a column called `.rownames`.
* For observations where no fitted values or summaries are available (where there's missing data, for example), return `NA`.
* *The `augment()` method should always return as many rows as were in `data` or `newdata`*, depending on which is supplied

{{% note %}} The recommended interface and functionality for `augment()` methods may change soon. {{%/ note %}}

## Document the new methods

The only remaining step is to integrate the new methods into the parent package! To do so, just drop the methods into a `.R` file inside of the `/R` folder and document them using roxygen2. If you're unfamiliar with the process of documenting objects, you can read more about it [here](http://r-pkgs.had.co.nz/man.html). Here's an example of how our `tidy.lm()` method might be documented:


```r
#' Tidy a(n) lm object
#'
#' @param x A `lm` object.
#' @param conf.int Logical indicating whether or not to include 
#'   a confidence interval in the tidied output. Defaults to FALSE.
#' @param conf.level The confidence level to use for the confidence 
#'   interval if conf.int = TRUE. Must be strictly greater than 0 
#'   and less than 1. Defaults to 0.95, which corresponds to a 
#'   95 percent confidence interval.
#' @param ... Unused, included for generic consistency only.
#' @return A tidy [tibble::tibble()] summarizing component-level
#'   information about the model
#'
#' @examples
#' # load the trees dataset
#' data(trees)
#' 
#' # fit a linear model on timber volume
#' trees_model <- lm(Volume ~ Girth + Height, data = trees)
#'
#' # summarize model coefficients in a tidy tibble!
#' tidy(trees_model)
#'
#' @export
tidy.lm <- function(x, conf.int = FALSE, conf.level = 0.95, ...) {

  # ... the rest of the function definition goes here!
```

Once you've documented each of your new methods and executed `devtools::document()`, you're done! Congrats on implementing your own broom tidier methods for a new model object!

## 용어집: 인수와 열이름 {#glossary}



Tidier methods have a standardized set of acceptable argument and output column names. The currently acceptable argument names by tidier method are:

<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
  <tr>
   <th style="text-align:left;"> Method </th>
   <th style="text-align:left;"> Argument </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> alpha </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> boot_se </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> by_class </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> col.names </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> component </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> conf.int </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> conf.level </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> conf.method </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> conf.type </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> diagonal </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> droppars </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> effects </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> ess </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> estimate.method </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> exponentiate </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> fe </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> include_studies </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> instruments </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> intervals </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> matrix </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> measure </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> na.rm </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> object </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> p.values </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> par_type </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> parameters </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> parametric </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> pars </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> prob </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> region </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> return_zeros </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> rhat </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> robust </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> scales </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> se.type </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> strata </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> test </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> trim </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> upper </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> deviance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> diagnostics </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> looic </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> mcmc </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> test </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> x </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> data </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> interval </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> newdata </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> se_fit </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> type.predict </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> type.residuals </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> weights </td>
  </tr>
</tbody>
</table>

The currently acceptable column names by tidier method are:

<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
  <tr>
   <th style="text-align:left;"> Method </th>
   <th style="text-align:left;"> Column </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> acf </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> adj.p.value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> alternative </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> at.value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> at.variable </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> atmean </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> autocorrelation </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> bias </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> ci.width </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> class </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> cluster </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> coef.type </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> column1 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> column2 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> comp </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> comparison </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> component </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> conf.high </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> conf.low </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> contrast </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> cumulative </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> cutoff </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> delta </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> den.df </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> denominator </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> dev.ratio </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> df </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> distance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> estimate </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> estimate1 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> estimate2 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> event </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> exp </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> expected </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> fpr </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> freq </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> GCV </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> group </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> group1 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> group2 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> index </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> item1 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> item2 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> kendall_score </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> lag </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> lambda </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> letters </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> lhs </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> logLik </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> mcmc.error </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> mean </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> meansq </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> method </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> n </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> N </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> n.censor </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> n.event </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> n.risk </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> null.value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> num.df </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> nzero </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> obs </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> op </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> outcome </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> p </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> p.value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> p.value.Sargan </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> p.value.weakinst </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> p.value.Wu.Hausman </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> parameter </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> PC </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> percent </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> power </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> proportion </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> pyears </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> response </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> rhs </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> robust.se </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> row </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> scale </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> sd </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> series </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> sig.level </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> size </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> spec </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> state </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> statistic </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> statistic.Sargan </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> statistic.weakinst </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> statistic.Wu.Hausman </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> std_estimate </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> std.all </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> std.dev </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> std.error </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> std.lv </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> std.nox </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> step </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> strata </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> stratum </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> study </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> sumsq </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> tau </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> term </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> time </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> tpr </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> type </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> uniqueness </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> var_kendall_score </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> variable </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> variance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> withinss </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> y.level </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> y.value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> tidy </td>
   <td style="text-align:left;"> z </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> adj.r.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> agfi </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> AIC </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> AICc </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> alpha </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> alternative </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> autocorrelation </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> avg.silhouette.width </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> betweenss </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> BIC </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> cfi </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> chi.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> chisq </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> cochran.qe </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> cochran.qm </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> conf.high </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> conf.low </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> converged </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> convergence </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> crit </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> cv.crit </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> den.df </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> deviance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> df </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> df.null </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> df.residual </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> dw.original </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> dw.transformed </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> edf </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> estimator </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> events </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> finTol </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> function.count </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> G </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> g.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> gamma </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> gradient.count </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> H </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> h.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> hypvol </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> i.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> independence </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> isConv </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> iter </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> iterations </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> kHKB </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> kLW </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> lag.order </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> lambda </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> lambda.1se </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> lambda.min </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> lambdaGCV </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> logLik </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> max.cluster.size </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> max.hazard </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> max.time </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> maxit </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> MCMC.burnin </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> MCMC.interval </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> MCMC.samplesize </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> measure </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> median </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> method </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> min.hazard </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> min.time </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> missing_method </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> model </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> n </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> n.clusters </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> n.factors </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> n.max </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> n.start </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> nevent </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> nexcluded </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> ngroups </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> nobs </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> norig </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> npar </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> npasses </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> null.deviance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> nulldev </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> num.df </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> number.interaction </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> offtable </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.cochran.qe </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.cochran.qm </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.original </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.Sargan </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.transformed </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.weak.instr </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> p.value.Wu.Hausman </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> parameter </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> pen.crit </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> power </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> power.reached </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> pseudo.r.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> r.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> records </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> residual.deviance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rho </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rho2 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rho20 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rmean </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rmean.std.error </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rmsea </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rmsea.conf.high </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> rscore </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> score </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> sigma </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> sigma2_j </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> spar </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> srmr </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> statistic </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> statistic.Sargan </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> statistic.weak.instr </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> statistic.Wu.Hausman </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> tau </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> tau.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> tau.squared.se </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> theta </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> timepoints </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> tli </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> tot.withinss </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> total </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> total.variance </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> totss </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> value </td>
  </tr>
  <tr>
   <td style="text-align:left;"> glance </td>
   <td style="text-align:left;"> within.r.squared </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .class </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .cluster </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .cochran.qe.loo </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .col.prop </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .conf.high </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .conf.low </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .cooksd </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .cov.ratio </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .cred.high </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .cred.low </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .dffits </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .expected </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .fitted </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .fitted_j_0 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .fitted_j_1 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .hat </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .lower </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .moderator </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .moderator.level </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .observed </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .probability </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .prop </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .remainder </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .resid </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .resid_j_0 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .resid_j_1 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .row.prop </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .rownames </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .se.fit </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .seasadj </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .seasonal </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .sigma </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .std.resid </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .tau </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .tau.squared.loo </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .trend </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .uncertainty </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .upper </td>
  </tr>
  <tr>
   <td style="text-align:left;"> augment </td>
   <td style="text-align:left;"> .weight </td>
  </tr>
</tbody>
</table>

The [alexpghayes/modeltests](https://github.com/alexpghayes/modeltests) package provides unit testing infrastructure to check your new tidier methods. Please file an issue there to request new arguments/columns to be added to the glossaries!

## Session information


```
#> - Session info  ----------------------------------------------------
#>  hash: man cook: light skin tone, ten o’clock, woman judge: light skin tone
#> 
#>  setting  value
#>  version  R version 4.1.2 (2021-11-01)
#>  os       Windows 10 x64 (build 19042)
#>  system   x86_64, mingw32
#>  ui       RTerm
#>  language (EN)
#>  collate  Korean_Korea.949
#>  ctype    Korean_Korea.949
#>  tz       Asia/Seoul
#>  date     2021-12-15
#>  pandoc   2.11.4 @ C:/Program Files/RStudio/bin/pandoc/ (via rmarkdown)
#> 
#> - Packages ---------------------------------------------------------
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.10  2021-10-31 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.2)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.1)
#>  generics   * 0.1.1   2021-10-25 [1] CRAN (R 4.1.2)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.2)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.2)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.2)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.2)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.2)
#>  rlang        0.4.12  2021-10-18 [1] CRAN (R 4.1.2)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.2)
#>  tibble     * 3.1.6   2021-11-07 [1] CRAN (R 4.1.2)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.1.2)
#>  tidyverse  * 1.3.1   2021-04-15 [1] CRAN (R 4.1.2)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.1.2)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.1.2)
#>  yardstick  * 0.0.9   2021-11-22 [1] CRAN (R 4.1.2)
#> 
#>  [1] C:/Program Files/R/R-4.1.2/library
#> 
#> --------------------------------------------------------------------
```
