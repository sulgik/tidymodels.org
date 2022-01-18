---
title: "분할표 통계분석"
tags: [infer]
categories: [statistical analysis]
type: learn-subsection
weight: 5
description: | 
  독립성 검정과 적합성 검정으로 카운트 테이블을 분석한다.
---






## 들어가기

이장은 tidymodels 패키지 설치만 필요합니다.

이 vignette 에서, infer 를 이용한 `\(\chi^2\)`(카이제곱) 독립성 검정과 카이제곱 적합도(goodness of fit) 검정 수행을 따라해 볼 것입니다.
두 개의 범주형 변수들 사이의 연관성을 검정하는데 사용할 수 있는 검정 독립성검정부터 시작할 것입니다.
그 다음, 하나의 범주형 변수의 분포가 어떤 이론적 분포로 얼마나 잘 근사시킬 수 있는지를 검정하는 카이제곱 적합도 검정으로 넘어 갈 것입니다.

이 vignette 에서, `ad_data` 데이터셋을 사용할 것입니다 (tidymodels 에 포함된 modeldata 패키지에 있음). 이 데이터셋은 인지 장애를 가진 333 명의 환자와 관련이 있습니다 ([Craig-Schapiro _et al_ (2011)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3079734/)). `?ad_data` 로 자세한 정보를 살펴보세요. 이 데이터의 주된 연구 주제는 Apolipoprotein E 유전자와 관련된 유전형이 인지능력에 영향을 어떻게 주는가 하는가입니다. 데이터는 다음과 같습니다:


```r
library(tidymodels) # Includes the infer package

data(ad_data, package = "modeldata")
ad_data %>%
  select(Genotype, Class)
#> # A tibble: 333 × 2
#>    Genotype Class   
#>    <fct>    <fct>   
#>  1 E3E3     Control 
#>  2 E3E4     Control 
#>  3 E3E4     Control 
#>  4 E3E4     Control 
#>  5 E3E3     Control 
#>  6 E4E4     Impaired
#>  7 E2E3     Control 
#>  8 E2E3     Control 
#>  9 E3E3     Control 
#> 10 E2E3     Impaired
#> # … with 323 more rows
```

주된 유전형은 E2, E3, E4 입니다. `Genotype` 의 값은 부모로부터 물려받은 것에 기반하여 환자의 유전형을 나타냅니다 (즉, "E2E4" 은 부모중 한명에게 E2, 다른 한명으로 부터 E4 를 받은 것을 의미합니다).

## 독립성 검정

카이제곱 독립성 검정을 수행하기 위해, 인지능력 (장애 혹은 정상) 과 유전형 사이의 연관성을 테스트해 볼 것입니다. 샘플데이터에서 이 둘의 관계성은 다음과 같습니다:

<img src="figs/plot-indep-1.svg" width="672" />

관계성이 없다면, 인지능력에 상관없이 보라색 막대가 같은 길이가 되어야 합니다. 하지만, 우리가 여기서 보는 차이점은 랜덤 노이즈 때문인가요?

`specify()` 와 `calculate()` 을 사용하여 관측 통계량을 계산할 수 있습니다.


```r
# calculate the observed statistic
observed_indep_statistic <- ad_data %>%
  specify(Genotype ~ Class) %>%
  calculate(stat = "Chisq")
```

관측된 `\(\chi^2\)` 통계량은 21.577 입니다. 이제, 이 값을, 변수들이 사실 관련되지 않았다는 가정 하에서 생성한 영 분포와 비교해 봐야 합니다. 그래야만, 인지능력과 유전형 사이의 연관성이 실제로 없을 때 이 관측된 통계량을 볼 가능성이 얼마나 되는지 알 수 있습니다.

영 분포를 생성(`generate()`)하는 방법은 두 가지 입니다: 랜더마이제이션이나 이론기반 방법을 사용할 수 있습니다. 랜더마이제이션 방법은 반응변수와 설명변수를 섞어서 각 사람의 유전형이 샘플의 랜덤한 인지점수와 짝을 이루도록 합니다. 이렇게 하면, 둘 사이의 연관성이 깨집니다.


```r
# generate the null distribution using randomization
null_distribution_simulated <- ad_data %>%
  specify(Genotype ~ Class) %>%
  hypothesize(null = "independence") %>%
  generate(reps = 5000, type = "permute") %>%
  calculate(stat = "Chisq")
```

위의 `specify(Genotype ~ Class)` 라인에서 동일한 문법인 `specify(response = Genotype, explanatory = Class)` 를 사용할 수도 있습니다. 랜더마이제이션 대신 이론기반 방법을 사용하여 영분포를 생성하는 아래의 코드에서도 마찬가지 입니다.


```r
# generate the null distribution by theoretical approximation
null_distribution_theoretical <- ad_data %>%
  specify(Genotype ~ Class) %>%
  hypothesize(null = "independence") %>%
  # note that we skip the generation step here!
  calculate(stat = "Chisq")
```

이 분포들과 우리 관측한 통계량이 어디 떨어지는지를 보기 위해, `visualize()` 를 사용할 수 있습니다:


```r
# visualize the null distribution and test statistic!
null_distribution_simulated %>%
  visualize() + 
  shade_p_value(observed_indep_statistic,
                direction = "greater")
```

<img src="figs/visualize-indep-1.svg" width="672" />

이론적 영분포를 배경으로 관측한 통계량을 시각화 할 수 있습니다. 이론방법을 사용할 때 `generate()` 와 `calculate()` 단계를 생략하고, `visualize()` 에 `method = "theoretical"` 를 설정해야 합니다.


```r
# visualize the theoretical null distribution and test statistic!
ad_data %>%
  specify(Genotype ~ Class) %>%
  hypothesize(null = "independence") %>%
  visualize(method = "theoretical") + 
  shade_p_value(observed_indep_statistic,
                direction = "greater")
```

<img src="figs/visualize-indep-theor-1.svg" width="672" />

랜덤마이제이션 기반과 이론적 영분포 모두를 시각화하여, 둘이 어떻게 연관되는지를 이해하기 위해, 랜더마이제이션 기반 영분포를 `visualize()` 로 파이핑하고, `method = "both"` 를 설정할 수 있습니다.


```r
# visualize both null distributions and the test statistic!
null_distribution_simulated %>%
  visualize(method = "both") + 
  shade_p_value(observed_indep_statistic,
                direction = "greater")
```

<img src="figs/visualize-indep-both-1.svg" width="672" />

어떤 경우에도, 인지력과 유전형 사이에 연관성이 없는 상황에서 우리 관측 검정 통계량은 꽤 일어나기 힘듭니다. 더 정확하게, p-값을 계산할 수 있습니다:


```r
# calculate the p value from the observed statistic and null distribution
p_value_independence <- null_distribution_simulated %>%
  get_p_value(obs_stat = observed_indep_statistic,
              direction = "greater")

p_value_independence
#> # A tibble: 1 × 1
#>   p_value
#>     <dbl>
#> 1  0.0002
```

따라서, 인지력과 유전형 사이에 관계성이 없을 때, 통계량이 21.577 보다 같거나 더 극단적이 될 확률은 약 2\times 10^{-4} 입니다.

위에서 본 단계들과 동일하게, 해당 패키지는 타이디한 데이터에 카이제곱 독립성 검정을 수행하는 래퍼 함수, `chisq_test` 를 제공합니다. 문법은 다음과 같습니다:


```r
chisq_test(ad_data, Genotype ~ Class)
#> # A tibble: 1 × 3
#>   statistic chisq_df  p_value
#>       <dbl>    <int>    <dbl>
#> 1      21.6        5 0.000630
```


## 적합성 (Goodness of fit)

이제, 카이제곱 적합성 검정으로 넘어가서, 유전자형 데이터만 살펴볼 것입니다. 
Apolipoprotein E 와 질병 사이의 관계성을 조사한 논문들이 많이 있습니다. 
예를 들어, [Song _et al_ (2004)](https://annals.org/aim/article-abstract/717641/meta-analysis-apolipoprotein-e-genotypes-risk-coronary-heart-disease) 에서는 이 유전자와 심장 질환을 조사한 많은 연구의 메타-분석을 수행했습니다. 이 논문에서, 많은 샘플 중 다른 유전자형의 빈도를 보고합니다. 우리 유전자형 샘플이 논문과 일관성이 있는지 보는 것은 흥미로울 수 있습니다 (이 분석에서 빈도를 안다고 가정함).

메타-분석과 우리 관측 데이터의 빈도는 다음과 같다:


```r
# Song, Y., Stampfer, M. J., & Liu, S. (2004). Meta-Analysis: Apolipoprotein E 
# Genotypes and Risk for Coronary Heart Disease. Annals of Internal Medicine, 
# 141(2), 137.
meta_rates <- c("E2E2" = 0.71, "E2E3" = 11.4, "E2E4" = 2.32,
                "E3E3" = 61.0, "E3E4" = 22.6, "E4E4" = 2.22)
meta_rates <- meta_rates/sum(meta_rates) # these add up to slightly > 100%

obs_rates <- table(ad_data$Genotype)/nrow(ad_data)
round(cbind(obs_rates, meta_rates) * 100, 2)
#>      obs_rates meta_rates
#> E2E2       0.6       0.71
#> E2E3      11.1      11.37
#> E2E4       2.4       2.31
#> E3E3      50.1      60.85
#> E3E4      31.8      22.54
#> E4E4       3.9       2.21
```

영가설은 `Genotype` 이 메타-분석과 같은 빈도 분포를 따른다고 가정합시다. 분포에서 이 차이가 통계적으로 유의한지 검정해 봅시다. 

우선, 가설 검정을 수행하기 위해, 우리 관측 통계량을 계산합니다.


```r
# calculating the null distribution
observed_gof_statistic <- ad_data %>%
  specify(response = Genotype) %>%
  hypothesize(null = "point", p = meta_rates) %>%
  calculate(stat = "Chisq")
```

관측된 통계량은 23.384 입니다. 
이제 `generate()` 호출 하나로 영분포를 생성합니다:


```r
# generating a null distribution
null_distribution_gof <- ad_data %>%
  specify(response = Genotype) %>%
  hypothesize(null = "point", p = meta_rates) %>%
  generate(reps = 5000, type = "simulate") %>%
  calculate(stat = "Chisq")
```

한번 더, 이러한 분포가 어떻게 생격고, 관측 통계량이 어디에 떨어지는지 알기 위해, 시각화(`visualize()`)할 수 있습니다:


```r
# visualize the null distribution and test statistic!
null_distribution_gof %>%
  visualize() + 
  shade_p_value(observed_gof_statistic,
                direction = "greater")
```

<img src="figs/visualize-indep-gof-1.svg" width="672" />

이 통계량은 우리 빈도가 메타-분석의 빈도와 같다면, 이 통계량이 일어나기 힘든 것 같습니다! 그런데 얼마나 그런가요? p-값을 계산합니다:


```r
# calculate the p-value
p_value_gof <- null_distribution_gof %>%
  get_p_value(observed_gof_statistic,
              direction = "greater")

p_value_gof
#> # A tibble: 1 × 1
#>   p_value
#>     <dbl>
#> 1  0.0016
```

따라서, Song 논문과 각 유전자형이 같은 빈도로 일어난다면, 우리가 관측한 것과 같은 분포를 볼 확률은 약 0.002 입니다.

위에서 본 단계들과 동일하게, 해당 패키지는 타이디한 데이터에 카이제곱 독립성 검정을 수행하는 래퍼 함수, `chisq_test` 를 제공합니다. 문법은 다음과 같습니다:


```r
chisq_test(ad_data, response = Genotype, p = meta_rates)
#> # A tibble: 1 × 3
#>   statistic chisq_df  p_value
#>       <dbl>    <dbl>    <dbl>
#> 1      23.4        5 0.000285
```



## 세션정보


```
#> ─ Session info  🕺🏾  🛌🏻  💜   ───────────────────────────────────────
#>  hash: man dancing: medium-dark skin tone, person in bed: light skin tone, purple heart
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
#>  date     2022-01-18
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
 
