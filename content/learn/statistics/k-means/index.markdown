---
title: "타이디 데이터 원칙과 함께 K-means 클러스터링"
tags: [broom]
categories: [statistical analysis]
type: learn-subsection
weight: 2
description: | 
  Summarize clustering characteristics and estimate the best number of clusters for a data set.
---





## 들어가기

이 장은 tidymodels 패키지만 필요로 합니다.

K-means 클러스터링 통계 분석에 타이디 데이터 원칙들을 적용하는 유용한 예제로 볼 수 있습니다. 특별히 다음의 타이디하게 하는 함수들 사이에 차이점을 볼 수 있습니다: 

- `tidy()`
- `augment()` 
- `glance()`

세 클러스터를 이루는 랜덤 2차원 데이터를 생성하는 것부터 시작해봅시다. 각 클러스터의 데이터는 다른 평균을 가지는 다변량 가우시안 분포로부터 생성될 것입니다:


```r
library(tidymodels)

set.seed(27)

centers <- tibble(
  cluster = factor(1:3), 
  num_points = c(100, 150, 50),  # number points in each cluster
  x1 = c(5, 0, -3),              # x1 coordinate of cluster center
  x2 = c(-1, 1, -2)              # x2 coordinate of cluster center
)

labelled_points <- 
  centers %>%
  mutate(
    x1 = map2(num_points, x1, rnorm),
    x2 = map2(num_points, x2, rnorm)
  ) %>% 
  select(-num_points) %>% 
  unnest(cols = c(x1, x2))

ggplot(labelled_points, aes(x1, x2, color = cluster)) +
  geom_point(alpha = 0.3)
```

<img src="figs/unnamed-chunk-1-1.svg" width="672" />

k-means 클러스터링을 하기 이상적인 케이스입니다.

## K-means 는 어떻게 작동하나요?

공식을 사용하기보다, Allison Horst 의 [artwork](https://github.com/allisonhorst/stats-illustrations) 를 이용한 이 짧은 애니메이션은 클러스터링 프로세스를 설명합니다:

<img src="kmeans.gif" style="display: block; margin: auto;" />

## R 에서 클러스터링


메인 입력인수가 모든 컬럼이 수치형인 데이터프레임인 빌트인 `kmeans()` 함수를 사용할 것입니다.


```r
points <- 
  labelled_points %>% 
  select(-cluster)

kclust <- kmeans(points, centers = 3)
kclust
#> K-means clustering with 3 clusters of sizes 148, 51, 101
#> 
#> Cluster means:
#>        x1    x2
#> 1  0.0885  1.05
#> 2 -3.1429 -2.00
#> 3  5.0040 -1.05
#> 
#> Clustering vector:
#>   [1] 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3
#>  [38] 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3
#>  [75] 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 1 1 1 1 1 1 1 1 1 1 1
#> [112] 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
#> [149] 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
#> [186] 1 1 1 1 1 1 1 1 1 1 1 1 1 3 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
#> [223] 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2
#> [260] 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
#> [297] 2 2 2 2
#> 
#> Within cluster sum of squares by cluster:
#> [1] 299 109 243
#>  (between_SS / total_SS =  82.5 %)
#> 
#> Available components:
#> 
#> [1] "cluster"      "centers"      "totss"        "withinss"     "tot.withinss"
#> [6] "betweenss"    "size"         "iter"         "ifault"
summary(kclust)
#>              Length Class  Mode   
#> cluster      300    -none- numeric
#> centers        6    -none- numeric
#> totss          1    -none- numeric
#> withinss       3    -none- numeric
#> tot.withinss   1    -none- numeric
#> betweenss      1    -none- numeric
#> size           3    -none- numeric
#> iter           1    -none- numeric
#> ifault         1    -none- numeric
```

출력은 길이가 다른 요소들의 벡터들로 이루어진 리스트입니다. 
원 데이터셋과 같은 길이가 300 인 것이 하나 있습니다.
길이가 3 인 두 요소 (`withinss` and `tot.withinss`) 가 있고, `centers` 는 행이 3 인 행렬입니다. 그리고 나서 길이가 1 인 요소들이 있습니다: `totss`, `tot.withinss`, `betweenss`, `iter`. (`ifault` 값은 가능항 알고리즘 문제들을 가리킵니다.)

우리 데이터셋을 타이디하게 하고 싶을 때 이 다른 길이들은 중요한 의미를 갖습니다; 그들은 각 유형의 구성요소들이 *다른 종류* 의 정보를 소통함을 상징합니다.

- `cluster` (300 개의 값들) 는 각 *점* 에 관한 정보가 있습니다
- `centers`, `withinss`, `size` (3 values) 는 각 *클러스터* 에 관한 정보가 있습니다
- `totss`, `tot.withinss`, `betweenss`, `iter` (1 값) 에는 *full clustering* 에 관한 정보가 있습니다

이 것들 중 어떤 것을 추출하고 싶을까요? 정답은 없습니다; 분석가는 각각에 관심이 있을 수 있습니다. 이것들은 완전히 다른 정보 (이것들을 결합하는 직관적인 방법이 없다는 것은 말할 필요도 없음) 를 제공하기 때문에, 추출하기 위해서 구분된 함수들이 사용됩니다. `augment` 는 point 분류를 원 데이터셋에 추가합니다:


```r
augment(kclust, points)
#> # A tibble: 300 × 3
#>       x1     x2 .cluster
#>    <dbl>  <dbl> <fct>   
#>  1  6.91 -2.74  3       
#>  2  6.14 -2.45  3       
#>  3  4.24 -0.946 3       
#>  4  3.54  0.287 3       
#>  5  3.91  0.408 3       
#>  6  5.30 -1.58  3       
#>  7  5.01 -1.77  3       
#>  8  6.16 -1.68  3       
#>  9  7.13 -2.17  3       
#> 10  5.24 -2.42  3       
#> # … with 290 more rows
```

`tidy()` 함수는 클러스터별 수준기반으로 요약합니다:


```r
tidy(kclust)
#> # A tibble: 3 × 5
#>        x1    x2  size withinss cluster
#>     <dbl> <dbl> <int>    <dbl> <fct>  
#> 1  0.0885  1.05   148     299. 1      
#> 2 -3.14   -2.00    51     109. 2      
#> 3  5.00   -1.05   101     243. 3
```

그리고 늘 그렇듯, `glance()` 함수는 단일행 요약을 추출합니다:


```r
glance(kclust)
#> # A tibble: 1 × 4
#>   totss tot.withinss betweenss  iter
#>   <dbl>        <dbl>     <dbl> <int>
#> 1 3724.         651.     3073.     2
```

## 탐색적 클러스터링

While these summaries are useful, they would not have been too difficult to extract out from the data set yourself. The real power comes from combining these analyses with other tools like [dplyr](https://dplyr.tidyverse.org/).

Let's say we want to explore the effect of different choices of `k`, from 1 to 9, on this clustering. First cluster the data 9 times, each using a different value of `k`, then create columns containing the tidied, glanced and augmented data:


```r
kclusts <- 
  tibble(k = 1:9) %>%
  mutate(
    kclust = map(k, ~kmeans(points, .x)),
    tidied = map(kclust, tidy),
    glanced = map(kclust, glance),
    augmented = map(kclust, augment, points)
  )

kclusts
#> # A tibble: 9 × 5
#>       k kclust   tidied           glanced          augmented         
#>   <int> <list>   <list>           <list>           <list>            
#> 1     1 <kmeans> <tibble [1 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 2     2 <kmeans> <tibble [2 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 3     3 <kmeans> <tibble [3 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 4     4 <kmeans> <tibble [4 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 5     5 <kmeans> <tibble [5 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 6     6 <kmeans> <tibble [6 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 7     7 <kmeans> <tibble [7 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 8     8 <kmeans> <tibble [8 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
#> 9     9 <kmeans> <tibble [9 × 5]> <tibble [1 × 4]> <tibble [300 × 3]>
```

We can turn these into three separate data sets each representing a different type of data: using `tidy()`, using `augment()`, and using `glance()`. Each of these goes into a separate data set as they represent different types of data.


```r
clusters <- 
  kclusts %>%
  unnest(cols = c(tidied))

assignments <- 
  kclusts %>% 
  unnest(cols = c(augmented))

clusterings <- 
  kclusts %>%
  unnest(cols = c(glanced))
```

Now we can plot the original points using the data from `augment()`, with each point colored according to the predicted cluster.


```r
p1 <- 
  ggplot(assignments, aes(x = x1, y = x2)) +
  geom_point(aes(color = .cluster), alpha = 0.8) + 
  facet_wrap(~ k)
p1
```

<img src="figs/unnamed-chunk-8-1.svg" width="672" />

적절한 클러스터 개수 (3)와 `k` 가 너무 놓거나 낮을 때 k-means 알고리듬이 어떻게 작동하는지에 대해 좋은 감을 잠았습니다. `tidy()` 의 데이터를 이용하여 클러스터 중심들을 추가할 수 있습니다:


```r
p2 <- p1 + geom_point(data = clusters, size = 10, shape = "x")
p2
```

<img src="figs/unnamed-chunk-9-1.svg" width="672" />

`glance()` 의 데이터는 다르지만 동등하게 중요한 목적을 만족시킵니다; `k` 값에 따른 요약 통계량 트렌드를 보여줍니다. `tot.withiness` 열에 저장된 within sum of squares 이 특별히 중요합니다.


```r
ggplot(clusterings, aes(k, tot.withinss)) +
  geom_line() +
  geom_point()
```

<img src="figs/unnamed-chunk-10-1.svg" width="672" />

이는 클러스터 내 분산을 나타냅니다. `k` 가 증가할 수록 감소하지만, `k = 3` 주위에서 꺾임 (혹은 "팔꿈치(elbow)") 이 보입니다. 이 꺽임은 3차 이후의 추가 클러스터들이 거의 소용이 없음을 가리킵니다. (수학적으로 엄밀한 해석과 이 방법의 구현에 관해서는 [여기](https://web.stanford.edu/~hastie/Papers/gap.pdf) 를 살펴보세요). 따라서, broom 이 제공하는 타이디하게 하는 세가지 방법 모두 클러스터링 결과를 요약하는데 유용합니다.

## Session information


```
<<<<<<< HEAD
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
#>  date     2022-01-10
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
=======
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
#>  date     2022-01-10                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package    * version date       lib source        
#>  broom      * 0.7.9   2021-07-27 [1] CRAN (R 4.0.2)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.0.2)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.0.2)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.0.2)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.0.2)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.0.2)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.0.0)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.0.2)
#>  rlang        0.4.12  2021-10-18 [1] CRAN (R 4.0.2)
#>  rsample    * 0.1.0   2021-05-08 [1] CRAN (R 4.0.2)
#>  tibble     * 3.1.5   2021-09-30 [1] CRAN (R 4.0.2)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.0.2)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.0.2)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.0.2)
#>  yardstick  * 0.0.8   2021-03-28 [1] CRAN (R 4.0.2)
>>>>>>> 3e4670b1034c53493e55a78b23a09627e32f3890
#> 
#> ────────────────────────────────────────────────────────────────────
```

