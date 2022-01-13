---
title: "리샘플링과 타이디한 데이터를 이용한 가설검정"
tags: [infer]
categories: [statistical analysis]
type: learn-subsection
weight: 4
description: | 
  유연한 함수를 이용하여 통계추론을 위한 가설검정을 수행합니다.
---





## 들어가기

이 장은 tidymodels 패키지만 필요로 합니다.

tidymodels 패키지 [infer](https://tidymodels.github.io/infer/)는 `tidyverse` 디자인 프레임워크와 일관성을 보이는 통계추론을 수행하는 표현력 좋은 문법을 구현하는 데에 사용할 수 있습니다. 이 패키지는 특정 통계 검정을 제공하지 않고, 일반적은 가설 검정이 공유하는 원칙을 4 개의 메인 동사 (함수) 세트로 종합합니다 출력물로 부터 정보를 시각화하고 추출하는 도구들을 장착하였습니다.

우리가 어떤 가설 검정을 하던지와 상관 없이, 같은 종류의 질문을 할 것입니다.

>우리가 관측한 데이터에서의 효과나 차이가 실제인가, 아니면 단순히 우연인가? 

이 질문에 답하기 위해, 관측된 데이터는 "아무것도 일어나지 않는" 세계 (즉, 관측된 효과는 단순히 우연에 의한 것) ㅇ서 왔다고 가정하는 것으로 시작하고, 이 가정을 우리 **귀무가설(null hypothesis)** 라고 부릅니다. (실제로 귀무가설을 믿는 것은 전혀 아닙니다; 귀무가설과 반대인 **대립가설(alternative hypothesis)**은 관측데이터에 있는 효과가 "뭔가가 있는" 사실에 비롯되었다는 것입니다.) 우리는 데이터에서 관측된 효과를 기술하는 **검정통계량** 을 계산합니다. 이 검정 통계량을 이용하여 **p-값** 을 계산할 수 있는데, 이는 귀무가설이 사실일 때 우리 관측데이터가 일어날 확률입니다. 미리 정한 **유의수준** `\(\alpha\)` 이하이면 귀무가설을 기각할 수 있습니다.

가설 검정이 처음이라면 다음을 살펴봐야합니다.

* [Section 9.2 of _Statistical Inference via Data Science_](https://moderndive.com/9-hypothesis-testing.html#understanding-ht)
* The American Statistical Association's recent [statement on p-values](https://doi.org/10.1080/00031305.2016.1154108) 

이 패키지의 워크플로는 이러한 생각으로 설계됩니다. 데이터셋이 주어지면,

+ `specify()` 는 관심있는 변수나 변수 사이의 관계를 설정합니다.
+ `hypothesize()` 는 귀무 가설을 선언합니다.
+ `generate()` 는 귀무가설을 반영하는 데이터를 생성합니다.
+ `calculate()` 는 생성된 데이터로 부터 통계량의 분포를 계산하여 영분포(null distribution)를 만듭니다.

이 vignette 에서, infer 에 있는 `gss` 데이터셋을 이용할 것인데, 이는 *General Social Survey* 의 11 개 변수를 가진 관측값 500 개의 샘플을 포함합니다.


```r
library(tidymodels) # Includes the infer package

# load in the data set
data(gss)

# take a look at its structure
dplyr::glimpse(gss)
#> Rows: 500
#> Columns: 11
#> $ year    <dbl> 2014, 1994, 1998, 1996, 1994, 1996, 1990, 2016, 2000, 1998, 20…
#> $ age     <dbl> 36, 34, 24, 42, 31, 32, 48, 36, 30, 33, 21, 30, 38, 49, 25, 56…
#> $ sex     <fct> male, female, male, male, male, female, female, female, female…
#> $ college <fct> degree, no degree, degree, no degree, degree, no degree, no de…
#> $ partyid <fct> ind, rep, ind, ind, rep, rep, dem, ind, rep, dem, dem, ind, de…
#> $ hompop  <dbl> 3, 4, 1, 4, 2, 4, 2, 1, 5, 2, 4, 3, 4, 4, 2, 2, 3, 2, 1, 2, 5,…
#> $ hours   <dbl> 50, 31, 40, 40, 40, 53, 32, 20, 40, 40, 23, 52, 38, 72, 48, 40…
#> $ income  <ord> $25000 or more, $20000 - 24999, $25000 or more, $25000 or more…
#> $ class   <fct> middle class, working class, working class, working class, mid…
#> $ finrela <fct> below average, below average, below average, above average, ab…
#> $ weight  <dbl> 0.896, 1.083, 0.550, 1.086, 1.083, 1.086, 1.063, 0.478, 1.099,…
```

각 행은 개인 조사답변인데, 설무자에 관한 기초 인구통계학정 정보와 추가적인 변수들이 있습니다. 포함된 변수들과 소스에 관한 정보는 `?gss` 로 알아볼 수 있습니다. 이 데이터 (와 이에 관한 우리의 예제) 는 보여주기 위한 목적이고 적절한 가중치가 없다면 정확한 추정값을 꼭 제공한다고 할 수 없습니다. 이 예에서, 이 데이터셋은 우리가 탐구하고자하는 모집단인 미국성인집단을 대표할 수 있는 샘플이라고 가정합시다.

## 변수 설정

The `specify()` 함수는 데이터셋에서 어떤 변수에 관심이 있는지를 설정하는데 사용할 수 있습니다. 만약 응답자의 `age` 에만 관심이 있다면, 다음과 같이 작성합니다:


```r
gss %>%
  specify(response = age)
#> Response: age (numeric)
#> # A tibble: 500 × 1
#>      age
#>    <dbl>
#>  1    36
#>  2    34
#>  3    24
#>  4    42
#>  5    31
#>  6    32
#>  7    48
#>  8    36
#>  9    30
#> 10    33
#> # … with 490 more rows
```


프론트엔드에서 보면, `specify()` 의 출력은 설정한 데이터프레임의 열들을 콕 찝는 것 처럼 보입니다. 이 객체의 클래스를 확인하고 싶으면 어떻게 할까요?


```r
gss %>%
  specify(response = age) %>%
  class()
#> [1] "infer"      "tbl_df"     "tbl"        "data.frame"
```

infer 클래스는 데이터프레임 클래스를 바탕으로 추가된 것임을 알 수 있습니다; 이 새로운 클래스는 메타데이터를 추가로 저장합니다.

두 개의 변수 (예를 들어 `age` 와 `partyid`) 에 관심이 있다면 이들의 관계를 두 방법 중 하나의 방법으로 설정(`specify()`)할 수 있습니다:


```r
# as a formula
gss %>%
  specify(age ~ partyid)
#> Response: age (numeric)
#> Explanatory: partyid (factor)
#> # A tibble: 500 × 2
#>      age partyid
#>    <dbl> <fct>  
#>  1    36 ind    
#>  2    34 rep    
#>  3    24 ind    
#>  4    42 ind    
#>  5    31 rep    
#>  6    32 rep    
#>  7    48 dem    
#>  8    36 ind    
#>  9    30 rep    
#> 10    33 dem    
#> # … with 490 more rows

# with the named arguments
gss %>%
  specify(response = age, explanatory = partyid)
#> Response: age (numeric)
#> Explanatory: partyid (factor)
#> # A tibble: 500 × 2
#>      age partyid
#>    <dbl> <fct>  
#>  1    36 ind    
#>  2    34 rep    
#>  3    24 ind    
#>  4    42 ind    
#>  5    31 rep    
#>  6    32 rep    
#>  7    48 dem    
#>  8    36 ind    
#>  9    30 rep    
#> 10    33 dem    
#> # … with 490 more rows
```

비율이나 비율의 차에 관한 추론을 하고 있다면, `success` 인수를 사용하여 `response` 변수의 어떤 수준이 성공(success) 인지 설정해야 합니다. 예를 들어, 대학 학위가 있는 모집단의 비율에 관심이 있다면, 다음 코드를 이용할 수 있습니다: 


```r
# specifying for inference on proportions
gss %>%
  specify(response = college, success = "degree")
#> Response: college (factor)
#> # A tibble: 500 × 1
#>    college  
#>    <fct>    
#>  1 degree   
#>  2 no degree
#>  3 degree   
#>  4 no degree
#>  5 degree   
#>  6 no degree
#>  7 no degree
#>  8 degree   
#>  9 degree   
#> 10 no degree
#> # … with 490 more rows
```

## 가설 선언

추론 파이프라인에서 다음 과정은 종종 `hypothesize()` 을 이용한 귀무가설 선언입니다. 첫번째 단계는 `null` "independence" 나 "point" 중 하나를 `null` 인수에 제공하는 것입니다. 귀무가설이 두 변수간 독립을 가정한다면, `hypothesize()` 에 제공해야하는 것은 이것으로 족합니다:


```r
gss %>%
  specify(college ~ partyid, success = "degree") %>%
  hypothesize(null = "independence")
#> Response: college (factor)
#> Explanatory: partyid (factor)
#> Null Hypothesis: independence
#> # A tibble: 500 × 2
#>    college   partyid
#>    <fct>     <fct>  
#>  1 degree    ind    
#>  2 no degree rep    
#>  3 degree    ind    
#>  4 no degree ind    
#>  5 degree    rep    
#>  6 no degree rep    
#>  7 no degree dem    
#>  8 degree    ind    
#>  9 degree    rep    
#> 10 no degree dem    
#> # … with 490 more rows
```

점 추정에 관한 추론을 하고 있다면, `p` (the true proportion of successes, between 0 and 1), `mu` (the true mean), `med` (the true median), `sigma` (the true standard deviation) 중 하나도 제공해야 합니다. 예를 들어, 귀무가설이 모집단에서 주당근무시간이 40 이다 이면 다음과 같이 작성합니다:


```r
gss %>%
  specify(response = hours) %>%
  hypothesize(null = "point", mu = 40)
#> Response: hours (numeric)
#> Null Hypothesis: point
#> # A tibble: 500 × 1
#>    hours
#>    <dbl>
#>  1    50
#>  2    31
#>  3    40
#>  4    40
#>  5    40
#>  6    53
#>  7    32
#>  8    20
#>  9    40
#> 10    40
#> # … with 490 more rows
```

프론트엔드에서 `hypothesize()` 출력 데이터프레임은 `specify()` 에서 나왔을 때와 거의 같은 것 같지만, infer 는 지금 당신의 귀무가설을 "알고있습니다".

## 분포 생성하기

`hypothesize()` 를 이용하여 귀무가설을 주장했다면, 이 가설에 기반하여 영분포를 구축할 수 있습니다. `type` 인수에서 제공된, 방법들 몇개 중 하나를 이용하여 이를 할 수 있습니다:

* `bootstrap`: 부트스트랩 샘플은 각 데이터에서 뽑힐 것인데, 각 데이터는 입력 샘플 사이즈와 같은 크기의 샘플을 (복원)샘플된 것입니다.
* `permute`: 각 데이터에서, 각 입력 값은 샘플의 새로운 아웃풋값으로 (비복원) 랜덤 할당될 것입니다.
* `simulate`: 값이 각 레프리킷의 `hypothesize()` 에서 설정된 파라미터를 가진 이론적 분포로부터 샘플될 것입니다. (이 옵션은 현재 점추정을 검정할 때만 적용할 수 있습니다.)

위의 우리 예제로 돌아가서, 주당 평균 근무시간에 관해 다음과 같이 작성할 수 있습니다:


```r
gss %>%
  specify(response = hours) %>%
  hypothesize(null = "point", mu = 40) %>%
  generate(reps = 5000, type = "bootstrap")
#> Response: hours (numeric)
#> Null Hypothesis: point
#> # A tibble: 2,500,000 × 2
#> # Groups:   replicate [5,000]
#>    replicate hours
#>        <int> <dbl>
#>  1         1  38.6
#>  2         1  33.6
#>  3         1  38.6
#>  4         1  35.6
#>  5         1  53.6
#>  6         1  38.6
#>  7         1  38.6
#>  8         1  28.6
#>  9         1  38.6
#> 10         1  48.6
#> # … with 2,499,990 more rows
```

위 예에서, 귀무 가설을 형성하기 위해 5000 개의 부트스트랩 샘플을 취합니다.

두 변수의 독립성에 관한 영분포를 생성하기 위해, 랜덤하게 설명변수와 반응변수의 쌍을 재셔플하여 기존 연관성을 끊어낼 수 있습니다.예를 들어, 소속정당은 나이에 영향을 받지 않는다는 가설 하에서 영분포를 생성 하기 위해 5000 레프리킷을 생성하는 법은:


```r
gss %>%
  specify(partyid ~ age) %>%
  hypothesize(null = "independence") %>%
  generate(reps = 5000, type = "permute")
#> Response: partyid (factor)
#> Explanatory: age (numeric)
#> Null Hypothesis: independence
#> # A tibble: 2,500,000 × 3
#> # Groups:   replicate [5,000]
#>    partyid   age replicate
#>    <fct>   <dbl>     <int>
#>  1 ind        36         1
#>  2 dem        34         1
#>  3 dem        24         1
#>  4 rep        42         1
#>  5 rep        31         1
#>  6 ind        32         1
#>  7 ind        48         1
#>  8 dem        36         1
#>  9 dem        30         1
#> 10 ind        33         1
#> # … with 2,499,990 more rows
```

## 통계량 계산

수행하는 추론이 계산기반인지 이론기반인지에 따라 `calculate()` 에게 각각 `generate()` 이거나 `hypothesis()` 를 제공해야할 것입니다. 이 함수들은, `stat` 인수를 입력으로 하는데, 현재 다음 중 하나가 되어야 합니다: `"mean"`, `"median"`, `"sum"`, `"sd"`, `"prop"`, `"count"`, `"diff in means"`, `"diff in medians"`, `"diff in props"`, `"Chisq"`, `"F"`, `"t"`, `"z"`, `"slope"`, `"correlation"`. 예를 들어, 위 예에서, 평균 주간근무시간의 영분포를 계산하는 것은:


```r
gss %>%
  specify(response = hours) %>%
  hypothesize(null = "point", mu = 40) %>%
  generate(reps = 5000, type = "bootstrap") %>%
  calculate(stat = "mean")
#> Response: hours (numeric)
#> Null Hypothesis: point
#> # A tibble: 5,000 × 2
#>    replicate  stat
#>        <int> <dbl>
#>  1         1  39.8
#>  2         2  40.5
#>  3         3  39.4
#>  4         4  40.5
#>  5         5  39.5
#>  6         6  40.0
#>  7         7  38.8
#>  8         8  39.4
#>  9         9  38.9
#> 10        10  39.5
#> # … with 4,990 more rows
```

여기에서 `calculate()` 의 출력은 1000 reaplicates 각각에 대해 샘플통계량 (이 경우 평균)을 보여줍니다. 평균, 중앙값, 비율, `\(t\)`, `\(z\)` 통계량에서 차이에 관한 추론을 수행한다면, 어떤 설명변수에서 차이를 봐야하는지에 관한 순서를 나타내는 `order` 인수를 제공해야 합니다. 
예를들어, 대학학위자와 그렇지 않은 그룹의 평균나이 차이를 알아보기 위해, 다음과 같이 작성합니다:


```r
gss %>%
  specify(age ~ college) %>%
  hypothesize(null = "independence") %>%
  generate(reps = 5000, type = "permute") %>%
  calculate("diff in means", order = c("degree", "no degree"))
#> Response: age (numeric)
#> Explanatory: college (factor)
#> Null Hypothesis: independence
#> # A tibble: 5,000 × 2
#>    replicate   stat
#>        <int>  <dbl>
#>  1         1 -0.223
#>  2         2 -1.30 
#>  3         3 -0.531
#>  4         4 -1.09 
#>  5         5  0.130
#>  6         6 -0.611
#>  7         7  1.35 
#>  8         8  0.288
#>  9         9  1.22 
#> 10        10  3.37 
#> # … with 4,990 more rows
```

## 기타 도구들

infer 패키지는 요약 통계량과 영 분포 에서 의미를 추출하는 도구들 몇몇을 제공합니다; 이 패키지는 다양한 함수를 제공합니다: 통계량이 분포 중 어디에 있는지를 시각화 (`visualize()`), p-값을 계산 (`get_p_value()`), 신뢰구간을 계산 (`get_confidence_interval()`).

설명을 위해, 주간 평균 근무시간이 40 시간인지 아닌지를 결정하는 예시로 돌아갈 것입니다. 


```r
# find the point estimate
point_estimate <- gss %>%
  specify(response = hours) %>%
  calculate(stat = "mean")

# generate a null distribution
null_dist <- gss %>%
  specify(response = hours) %>%
  hypothesize(null = "point", mu = 40) %>%
  generate(reps = 5000, type = "bootstrap") %>%
  calculate(stat = "mean")
```

(다음의 경고를 주목하세요: `Removed 1244 rows containing missing values.`. 이 가설 검정을 수행하고 있다면 이 경고에 주목할 필요가 있습니다.)

우리 점추정값 41.382 은 *꽤* 40 에 가까워 보이지만, 조금 다릅니다. 이 차이가 우연인지 모집단의 평균 주간 근무시간이 실제는 40 이 아닌지 알고 싶습니다.

영분포를 한번 시각화해볼 수 있습니다.


```r
null_dist %>%
  visualize()
```

<img src="figs/visualize-1.svg" width="672" />

우리 샘플의 관측통계량이 이 분포 어디에 위치할까요? `obs_stat` 인수를 사용하여 이를 설정할 수 있습니다.


```r
null_dist %>%
  visualize() +
  shade_p_value(obs_stat = point_estimate, direction = "two_sided")
```

<img src="figs/visualize2-1.svg" width="672" />

infer 에서는 우리 관측통계량만큼 (혹은 그 보다 더 극단적인) 영분포의 영역을 색칠했습니다. (또한, `shade_p_value()` 함수를 적용하기 위해 `+` 연산자를 사용합니다.) `visualize()` 는 ggplot2 의 플롯 객체를 데이터프레임 대신 출력하고, p-값 레이어 객체를 플롯객체에 추가하기 위해 `+` 연산자가 필요합니다. 빨간 막대는 영분포의 오른쪽 꼬리에서 약간 떨어져 있는 것 처럼보이기 때문에, 샘플평균값 41.382 시간은 평균이 실제로 40 시간일 가능성이 좀 낮습니다. 그런데 얼마나 낮은걸까요?


```r
# get a two-tailed p-value
p_value <- null_dist %>%
  get_p_value(obs_stat = point_estimate, direction = "two_sided")

p_value
#> # A tibble: 1 × 1
#>   p_value
#>     <dbl>
#> 1  0.0364
```

It looks like the p-value is 0.036, which is pretty small---if the true mean number of hours worked per week was actually 40, the probability of our sample mean being this far (1.382 hours) from 40 would be 0.036. This may or may not be statistically significantly different, depending on the significance level `\(\alpha\)` you decided on *before* you ran this analysis. If you had set `\(\alpha = .05\)`, then this difference would be statistically significant, but if you had set `\(\alpha = .01\)`, then it would not be.

To get a confidence interval around our estimate, we can write:


```r
# start with the null distribution
null_dist %>%
  # calculate the confidence interval around the point estimate
  get_confidence_interval(point_estimate = point_estimate,
                          # at the 95% confidence level
                          level = .95,
                          # using the standard error
                          type = "se")
#> # A tibble: 1 × 2
#>   lower_ci upper_ci
#>      <dbl>    <dbl>
#> 1     40.1     42.6
```

As you can see, 40 hours per week is not contained in this interval, which aligns with our previous conclusion that this finding is significant at the confidence level `\(\alpha = .05\)`.

## Theoretical methods

The infer package also provides functionality to use theoretical methods for `"Chisq"`, `"F"` and `"t"` test statistics. 

Generally, to find a null distribution using theory-based methods, use the same code that you would use to find the null distribution using randomization-based methods, but skip the `generate()` step. For example, if we wanted to find a null distribution for the relationship between age (`age`) and party identification (`partyid`) using randomization, we could write:


```r
null_f_distn <- gss %>%
   specify(age ~ partyid) %>%
   hypothesize(null = "independence") %>%
   generate(reps = 5000, type = "permute") %>%
   calculate(stat = "F")
```

To find the null distribution using theory-based methods, instead, skip the `generate()` step entirely:


```r
null_f_distn_theoretical <- gss %>%
   specify(age ~ partyid) %>%
   hypothesize(null = "independence") %>%
   calculate(stat = "F")
```

We'll calculate the observed statistic to make use of in the following visualizations; this procedure is the same, regardless of the methods used to find the null distribution.


```r
F_hat <- gss %>% 
  specify(age ~ partyid) %>%
  calculate(stat = "F")
```

Now, instead of just piping the null distribution into `visualize()`, as we would do if we wanted to visualize the randomization-based null distribution, we also need to provide `method = "theoretical"` to `visualize()`.


```r
visualize(null_f_distn_theoretical, method = "theoretical") +
  shade_p_value(obs_stat = F_hat, direction = "greater")
```

<img src="figs/unnamed-chunk-4-1.svg" width="672" />

To get a sense of how the theory-based and randomization-based null distributions relate, we can pipe the randomization-based null distribution into `visualize()` and also specify `method = "both"`


```r
visualize(null_f_distn, method = "both") +
  shade_p_value(obs_stat = F_hat, direction = "greater")
```

<img src="figs/unnamed-chunk-5-1.svg" width="672" />

That's it! This vignette covers most all of the key functionality of infer. See `help(package = "infer")` for a full list of functions and vignettes.


## Session information


```
#> ─ Session info  👌  👨🏻‍✈️  🎠   ───────────────────────────────────────
#>  hash: OK hand, man pilot: light skin tone, carousel horse
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
#>  date     2022-01-13
#>  pandoc   2.11.4 @ /Applications/RStudio.app/Contents/MacOS/pandoc/ (via rmarkdown)
#> 
#> ─ Packages ─────────────────────────────────────────────────────────
#>  package    * version date (UTC) lib source
#>  broom      * 0.7.11  2022-01-03 [1] CRAN (R 4.1.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.0)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.0)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.0)
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
 
