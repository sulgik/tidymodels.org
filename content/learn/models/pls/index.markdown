---
title: "Partial least squares 로 하는 다변량 분석"
tags: [recipes,rsample]
categories: [pre-processing]
type: learn-subsection
weight: 6
description: | 
  하나 이상의 결과가 있는 예측 모델을 만들고 적합하기.
---






## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: modeldata, pls, and tidymodels.

"다변량 분석" 은 다중 _아웃컴_ 을 모델링하고, 분석하고 예측하는 것을 의미합니다. 
일반적인 통계 도구들에는 다변량 버전이 있습니다. 
예를 들어, 예측할 두 개의 아웃컴을 의미하는 `y1`, `y2` 열을 가진 데이터셋이 있다고 가정해봅시다. 
`lm()` 함수는 다음과 같이 생겼습니다:


```r
lm(cbind(y1, y2) ~ ., data = dat)
```

이 `cbind` 호출은 꽤 이상한데, 전통적 공식 인프라가 동작방법의 결과입니다.
recipes 패키지는 다루기 훨씬 쉽습니다!
이 장에서 다중 아웃컴을 모델링하는 법을 살펴볼 것입니다.

우리가 사용할 데이터는 아웃컴이 세 개 입니다. `?modeldata::meats` 을 보면:

> "이 데이터는 Tecator Infratec Food 와 근거리 적외선 통신 법칙(NIT)의 주파수 범위 850 - 1050 nm 에서 작동하는 Feed Analyzier 에서 기록되었습니다. 각 샘플에는 습도, 지방, 단백질 성분이 다른 잘게 다져진 고기가 있습니다.

> "각 고기 샘플에 대해 데이터는 100 개의 흡수도 채널 스펙트럼과 습도(물), 지방, 단백질 성분으로 구성되어 있습니다. 흡수도는 spectrometer 가 측정한 `-log10` 의 transmittance 입니다. 퍼센트로 측정한 세 가지 성분은 분석 화학가가 정했습니다. 

화학 테스트를 이용하여 세 성분의 비율을 예측하는 것이 목적입니다. 
설명변수들에 높은 수준의 변수간 상관관계가 있는 경우가 많은데 이 경우가 그렇습니다. 

두 개의 데이터 행렬 (`endpoints` 와 `absorp` 라 부름) 를 가져와서 데이터프레임으로 묶는 것으로 시작해 봅시다:


```r
library(modeldata)
data(meats)
```

세 개의 _아웃컴_ 도 꽤 높은 상관관계를 가집니다.

## 데이터 전처리하기

선형 모형을 이용하여 아웃컴을 예측할 수 있으면, partial least squares (PLS) 이 이상적인 방법이다. 
PLS는 데이터를 관측할 수 없는 _숨겨진_ 변수들의 집합의 함수로 모델링 하는데, 숨겨진 변수는 주성분 분석 (PCA) 와 유사한 방법으로 유도한다.

PCA 와 달리 PLS 는 PLS 성분을 생성할 때 아웃컴 데이터를 이용할 수도 있다. 
PCA 와 같이 PLS 는 이 성분들로 설명되는 설명변수의 분산을 최대화하지만, 동시에 이 성분들과 아웃컴들 사이의 상관관계를 최대화 합니다.
이렇게 하여, PLS 는 설명변수와 반응변수의 분산을 _쫓아갑니다(chase)_.

분산과 공분산 작업을 하고 있기 때문에, 데이터를 표준화 해야 합니다.
레시피가 모든 변수를 센터링 하고 스케일 할 것입니다.

공식을 사용하는 다변량 아웃컴을 다루는 많은 베이스 R 함수들은 전통적인 공식 방법 작업을 하기 위해 공식의 왼편에 `cbind()` 를 사용해야 합니다. 
tidymodels 에서 레시피는 이렇게 할 필요가 없습니다; 아웃컴들이 왼편에 같이 심볼릭하게 "추가"될 수 있습니다:


```r
norm_rec <- 
  recipe(water + fat + protein ~ ., data = meats) %>%
  step_normalize(everything()) 
```

PLS 모델을 마무리하기 전에, 사용할 PLS 성분의 개수를 정해야 합니다.
RMSE 와 같은 성능지표를 사용하여 할 수 있습니다.
하지만, _설명변수와아웃컴각각_ 에 대해 성분이 설병하는 분산의 비율을 계산할 수도 있습니다. 
이렇게 하면 상황이 요구하는 증거의 수준에 기반하여 informed 선택을 할 수 있도록 합니다. 

데이터셋이 크지 않으므로, 리샘플링을 해서 비율들을 측정해 봅시다. 
10-폴드 크로스밸리데이션을 열번 반복하여, 90% 데이터로 PLS 모델을 만들고 따로 둔 10% 로 평가를 합니다.
100 개 모델 각각에 대해 비율을 추출하고 저장합니다.

[rsample](https://tidymodels.github.io/rsample/) 패키지를 사용하여 폴드들을 생성할 수 있고, [`prepper()`](https://tidymodels.github.io/rsample/reference/prepper.html) 함수를 이용하여 각 리샘플에 대해 레시피를 추정할 수 있습니다: 


```r
set.seed(57343)
folds <- vfold_cv(meats, repeats = 10)

folds <- 
  folds %>%
  mutate(recipes = map(splits, prepper, recipe = norm_rec))
```

## Partial least squares

복잡한 부분은 다음과 같습니다:

1. 설명변수와 반응변수 포맷을 pls 패키지가 필요로 하는 포맷으로 바꾸고,
2. 비율을 추정하기. 

첫번째 부분에서, 표준화된 반응변수와 설명변수가 두 개의 행렬로 포맷될 필요가 있습니다. 
레시피를 준비할 때, `retain = TRUE` 를 사용했기 때문에, 처리된 데이터를 다시 얻기 위해, `new_data = NULL` 와 함께, `bake()` 를 사용할 수 있습니다.
데이터를 행렬로 저장하기 위해, `composition = "matrix"` 옵션을 하면, 데이터를 티블로 저장하지 않고 필요한 포맷을 사용하게 됩니다.

pls 패키지는 간단한 공식이 모델을 규정하기를 기대하지만, 공식의 각 사이드는 _행렬을 표현_ 해야 합니다. 
다른말로 하면, 각 열이 행렬인 열이 두 개인 데이터셋이 필요합니다.
이를 하는 비밀은 두 행렬을 데이터프레임으로 추가할 때 `I()` 를 사용하여 두 행렬을 "보호하는 것"입니다.

설명되는 분산의 비율 계산은 설명변수에 대해서 간단합니다; `pls::explvar()` 함수가 계산할 수 있습니다. 
반응변수에 대해 이 과정은 더 복잡합니다.
이를 계산하는 준비된 함수는 명확하지는 않지만 계산하는 요약함수 내에 코드가 조금 있습니다 (아래 참고).

여기서 보이는 `get_var_explained()` 함수는 이 모든 계산을 하고 (설명변수, water, 등의) `components`, `source` 열과 이 성분들이 설명하는 변수의 비율 (`proportion`) 열이 있는 데이터프레임을 반환할 것입니다.


```r
library(pls)

get_var_explained <- function(recipe, ...) {
  
  # Extract the predictors and outcomes into their own matrices
  y_mat <- bake(recipe, new_data = NULL, composition = "matrix", all_outcomes())
  x_mat <- bake(recipe, new_data = NULL, composition = "matrix", all_predictors())
  
  # The pls package prefers the data in a data frame where the outcome
  # and predictors are in _matrices_. To make sure this is formatted
  # properly, use the `I()` function to inhibit `data.frame()` from making
  # all the individual columns. `pls_format` should have two columns.
  pls_format <- data.frame(
    endpoints = I(y_mat),
    measurements = I(x_mat)
  )
  # Fit the model
  mod <- plsr(endpoints ~ measurements, data = pls_format)
  
  # Get the proportion of the predictor variance that is explained
  # by the model for different number of components. 
  xve <- explvar(mod)/100 

  # To do the same for the outcome, it is more complex. This code 
  # was extracted from pls:::summary.mvr. 
  explained <- 
    drop(pls::R2(mod, estimate = "train", intercept = FALSE)$val) %>% 
    # transpose so that components are in rows
    t() %>% 
    as_tibble() %>%
    # Add the predictor proportions
    mutate(predictors = cumsum(xve) %>% as.vector(),
           components = seq_along(xve)) %>%
    # Put into a tidy format that is tall
    pivot_longer(
      cols = c(-components),
      names_to = "source",
      values_to = "proportion"
    )
}
```

각 리샘플에 해당하는 데이터프레임을 계산하고 다른 열에 결과를 저장합니다.


```r
folds <- 
  folds %>%
  mutate(var = map(recipes, get_var_explained),
         var = unname(var))
```

이 데이터를 추출하고 집계하기 위해, 간단한 행 바인딩을 사용하여 데이터를 수직으로 쌓을 수 있습니다.
대부분의 동작은 첫 15 개 성분에 일어나기 때문에, 데이터를 필터하고 _평균_ 비율을 계산해 봅시다.


```r
variance_data <- 
  bind_rows(folds[["var"]]) %>%
  filter(components <= 15) %>%
  group_by(components, source) %>%
  summarize(proportion = mean(proportion))
```

아래 플롯에서는, 단백질 측정값이 중요하면, 반응변수의 표현을 좋게 하기 위해 10 개 정도의 성분이 필요할 것이라는 것을 의미합니다.
설명변수 분산은 하나의 성분을 사용하여 극단적으로 잘 포착되는 것을 주목하세요.
이 데이터의 상관관계가 높기 때문입니다.


```r
ggplot(variance_data, aes(x = components, y = proportion, col = source)) + 
  geom_line(alpha = 0.5, size = 1.2) + 
  geom_point() 
```

<img src="figs/plot-1.svg" width="100%" />


## 세션정보


```
#> ─ Session info  🤷🏻  👉🏽  🔷   ───────────────────────────────────────
#>  hash: person shrugging: light skin tone, backhand index pointing right: medium skin tone, large blue diamond
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
#>  date     2022-03-01
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
#>  pls        * 2.8-0   2021-09-03 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        1.0.0   2022-01-26 [1] CRAN (R 4.1.2)
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
 
