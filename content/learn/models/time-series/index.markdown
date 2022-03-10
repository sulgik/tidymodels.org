---
title: "타이디한 리샘플링으로 시계열 모델링하기"
tags: [rsample]
categories: [model fitting, resampling]
type: learn-subsection
weight: 4
description: | 
  리샘플링을 사용하여 시계열 예측 성능 추정치를 계산합니다.
---






## 들어가기

이 장의 코드를 사용하려면, 다음의 패키지들을 인스톨해야합니다: forecast, sweep, tidymodels, timetk, and zoo.

"[Demo Week: Tidy Forecasting with sweep](https://www.business-science.io/code-tools/2017/10/25/demo_week_sweep.html)" 는 시계열에 타이디한 방법에 관한 좋은 글입니다. 
이 글에서는 rsample 을 분석에 사용하는데, [rolling forecast origin resampling](https://robjhyndman.com/hyndsight/crossvalidation/) 을 사용하여 미래 관측값에 관한 성능 추정값을 구합니다. 


## 예제 데이터

여기에서 사용할 데이터는 [세인트루이스 연방준비은행 웹사이트](https://fred.stlouisfed.org/series/S4248SM144NCEN) 에서 가져온 주류 음료 매출에 관한 것입니다.


```r
library(tidymodels)
library(modeldata)
library(ggplot2)
data("drinks")
glimpse(drinks)
#> Rows: 309
#> Columns: 2
#> $ date           <date> 1992-01-01, 1992-02-01, 1992-03-01, 1992-04-01, 1992-0…
#> $ S4248SM144NCEN <dbl> 3459, 3458, 4002, 4564, 4221, 4529, 4466, 4137, 4126, 4…
```

각 행은 월간 매출을 나타냅니다 (백만 미달러 단위). 


## 시계열 리샘플링

1 년 후 예측값이 필요하고, 우리 모델은 과거 20 년에서 가장 최근 데이터를 사용해야 한다고 가정합시다. 
이 리샘플링 스킴을 설정하기 위해:


```r
roll_rs <- rolling_origin(
  drinks, 
  initial = 12 * 20, 
  assess = 12,
  cumulative = FALSE
  )

nrow(roll_rs)
#> [1] 58

roll_rs
#> # Rolling origin forecast resampling 
#> # A tibble: 58 × 2
#>    splits           id     
#>    <list>           <chr>  
#>  1 <split [240/12]> Slice01
#>  2 <split [240/12]> Slice02
#>  3 <split [240/12]> Slice03
#>  4 <split [240/12]> Slice04
#>  5 <split [240/12]> Slice05
#>  6 <split [240/12]> Slice06
#>  7 <split [240/12]> Slice07
#>  8 <split [240/12]> Slice08
#>  9 <split [240/12]> Slice09
#> 10 <split [240/12]> Slice10
#> # … with 48 more rows
```

각 `split` 요소에는 리샘플에 관한 정보가 있습니다:


```r
roll_rs$splits[[1]]
#> <Analysis/Assess/Total>
#> <240/12/309>
```

플롯을 그릴 목적으로, 평가셋의 첫번째 날 기준으로 각 스플릿을 인덱싱합니다:


```r
get_date <- function(x) {
  min(assessment(x)$date)
}

start_date <- map(roll_rs$splits, get_date)
roll_rs$start_date <- do.call("c", start_date)
head(roll_rs$start_date)
#> [1] "2012-01-01" "2012-02-01" "2012-03-01" "2012-04-01" "2012-05-01"
#> [6] "2012-06-01"
```

이 resampling 스킴에는 58 개의 스플릿이 있어서, 58 개의 ARIMA 모델이 적합됩니다.

forecast 패키지의 `auto.arima()` 함수를 사용하여 모델을 생성합니다.
`analysis()` 와 `assessment()` rsample 함수는 데이터프레임을 반환한 후 다른 단계에서 timetk 패키지에 있는 함수를 사용하여 데이터를 `mod_dat` 이름의 객체로 변환합니다.


```r
library(forecast)  # for `auto.arima`
library(timetk)    # for `tk_ts`
library(zoo)       # for `as.yearmon`

fit_model <- function(x, ...) {
  # suggested by Matt Dancho:
  x %>%
    analysis() %>%
    # Since the first day changes over resamples, adjust it
    # based on the first date value in the data frame 
    tk_ts(start = .$date[[1]] %>% as.yearmon(), 
          frequency = 12, 
          silent = TRUE) %>%
    auto.arima(...)
}
```

새로운 열에 각 모델을 저장합니다:


```r
roll_rs$arima <- map(roll_rs$splits, fit_model)

# For example:
roll_rs$arima[[1]]
#> Series: . 
#> ARIMA(4,1,1)(0,1,2)[12] 
#> 
#> Coefficients:
#>          ar1     ar2    ar3     ar4     ma1    sma1    sma2
#>       -0.185  -0.024  0.358  -0.152  -0.831  -0.193  -0.324
#> s.e.   0.147   0.166  0.144   0.081   0.138   0.067   0.064
#> 
#> sigma^2 estimated as 72198:  log likelihood=-1591
#> AIC=3198   AICc=3199   BIC=3226
```

(추가된 열과 관련한 경고메세지가 있는데 무시할 수 있습니다.)


## 모델 성능

모델 적합을 사용하여, 두 가지 방법으로 성능을 측정해 봅시다:

 * _Interpolation_ 에러는 모델을 생성하기 위해 사용한 데이터에 모델이 얼마나 잘 맞는지를 측정합니다. 이는 holdout 방법을 사용하지 않기 때문에 값이 긍정적으로 산출될 것입니다.
 * _Extrapolation_ or _forecast_ 에러는 (모델적합에 사용되지 않은) 뒤따르는 연도의 데이터에서 모델 성능을 평가합니다.

각 경우에서, 평균절대퍼센트에러 (MAPE) 는 모델 적합을 측정하기 위해 사용되는 통계량입니다.
interpolation 오차는 `Arima` 객체에서 계산할 수 있습니다.
sweep 패키지의 `sw_glance()` 함수를 사용해서 쉽게 해 봅시다:


```r
library(sweep)

roll_rs$interpolation <- map_dbl(
  roll_rs$arima,
  function(x) 
    sw_glance(x)[["MAPE"]]
  )

summary(roll_rs$interpolation)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>    2.84    2.92    2.95    2.95    2.97    3.13
```

extrapolation 에러를 계산하기 위해서는 모델과 스플릿 객체들이 필요합니다.
이들을 사용해서:


```r
get_extrap <- function(split, mod) {
  n <- nrow(assessment(split))
  # Get assessment data
  pred_dat <- assessment(split) %>%
    mutate(
      pred = as.vector(forecast(mod, h = n)$mean),
      pct_error = ( S4248SM144NCEN - pred ) / S4248SM144NCEN * 100
    )
  mean(abs(pred_dat$pct_error))
}

roll_rs$extrapolation <- 
  map2_dbl(roll_rs$splits, roll_rs$arima, get_extrap)

summary(roll_rs$extrapolation)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>    2.37    3.23    3.63    3.65    4.11    5.45
```

이 에러 추정값은 시간별로 어떻게 되나요?


```r
roll_rs %>%
  select(interpolation, extrapolation, start_date) %>%
  pivot_longer(cols = matches("ation"), names_to = "error", values_to = "MAPE") %>%
  ggplot(aes(x = start_date, y = MAPE, col = error)) + 
  geom_point() + 
  geom_line()
```

<img src="figs/plot-1.svg" width="672" />

앞서 언급했듯이 interpolation 에러가 어느 정도 underestimate 인 것 같습니다.

`rolling_origin()` 를 고정 윈도 사이즈뿐만 아니라 calendar 기간에 걸쳐 사용할 수 있다는 점을 주목해 보세요.
고정 윈도 사이즈가 결측 데이터포인트나 날짜가 다른 월 특징 때문에 고정윈도 사이즈를 사용할 수 없는 특이한 시계열 데이터에 유용합니다.

아래의 예제에서 설명을 하는데, `drinks` 를 26 년의 중첩세트로 분할하고 월이 아닌 연도로 롤링합니다.
최종 결과에서 원 예시와 다른 작업을 수행한 것을 주목하세요; 새로운 케이스에서, 각 슬라이스는 1 개월이 아닌 전체 연도를 전진합니다.


```r
# The idea is to nest by the period to roll over,
# which in this case is the year.
roll_rs_annual <- drinks %>%
  mutate(year = as.POSIXlt(date)$year + 1900) %>%
  nest(data = c(date, S4248SM144NCEN)) %>%
  rolling_origin(
    initial = 20, 
    assess = 1, 
    cumulative = FALSE
  )

analysis(roll_rs_annual$splits[[1]])
#> # A tibble: 20 × 2
#>     year data             
#>    <dbl> <list>           
#>  1  1992 <tibble [12 × 2]>
#>  2  1993 <tibble [12 × 2]>
#>  3  1994 <tibble [12 × 2]>
#>  4  1995 <tibble [12 × 2]>
#>  5  1996 <tibble [12 × 2]>
#>  6  1997 <tibble [12 × 2]>
#>  7  1998 <tibble [12 × 2]>
#>  8  1999 <tibble [12 × 2]>
#>  9  2000 <tibble [12 × 2]>
#> 10  2001 <tibble [12 × 2]>
#> 11  2002 <tibble [12 × 2]>
#> 12  2003 <tibble [12 × 2]>
#> 13  2004 <tibble [12 × 2]>
#> 14  2005 <tibble [12 × 2]>
#> 15  2006 <tibble [12 × 2]>
#> 16  2007 <tibble [12 × 2]>
#> 17  2008 <tibble [12 × 2]>
#> 18  2009 <tibble [12 × 2]>
#> 19  2010 <tibble [12 × 2]>
#> 20  2011 <tibble [12 × 2]>
```

이러한 캘린더슬라이스를 접근하는 워크플로는 `bind_rows()` 를 사용하여 각 분석셋을 조인하는 것입니다.


```r
mutate(
  roll_rs_annual,
  extracted_slice = map(splits, ~ bind_rows(analysis(.x)$data))
)
#> # Rolling origin forecast resampling 
#> # A tibble: 6 × 3
#>   splits         id     extracted_slice   
#>   <list>         <chr>  <list>            
#> 1 <split [20/1]> Slice1 <tibble [240 × 2]>
#> 2 <split [20/1]> Slice2 <tibble [240 × 2]>
#> 3 <split [20/1]> Slice3 <tibble [240 × 2]>
#> 4 <split [20/1]> Slice4 <tibble [240 × 2]>
#> 5 <split [20/1]> Slice5 <tibble [240 × 2]>
#> 6 <split [20/1]> Slice6 <tibble [240 × 2]>
```


## 세션정보


```
#> ─ Session info  👧🏿  🙆🏽  🎅🏽   ───────────────────────────────────────
#>  hash: girl: dark skin tone, person gesturing OK: medium skin tone, Santa Claus: medium skin tone
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
#>  forecast   * 8.15    2021-06-01 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.0)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.0)
#>  rlang        1.0.0   2022-01-26 [1] CRAN (R 4.1.2)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  sweep      * 0.2.3   2020-07-10 [1] CRAN (R 4.1.0)
#>  tibble     * 3.1.6   2021-11-07 [1] CRAN (R 4.1.0)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.1.0)
#>  timetk     * 2.6.2   2021-11-16 [1] CRAN (R 4.1.0)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.1.0)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.1.0)
#>  yardstick  * 0.0.9   2021-11-22 [1] CRAN (R 4.1.0)
#>  zoo        * 1.8-9   2021-03-09 [1] CRAN (R 4.1.0)
#> 
#>  [1] /Library/Frameworks/R.framework/Versions/4.1/Resources/library
#> 
#> ────────────────────────────────────────────────────────────────────
```
 
