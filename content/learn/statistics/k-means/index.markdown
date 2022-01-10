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

This is an ideal case for k-means clustering. 

## How does K-means work?

Rather than using equations, this short animation using the [artwork](https://github.com/allisonhorst/stats-illustrations) of Allison Horst explains the clustering process:

<img src="kmeans.gif" style="display: block; margin: auto;" />

## Clustering in R

We'll use the built-in `kmeans()` function, which accepts a data frame with all numeric columns as it's primary argument.


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

The output is a list of vectors, where each component has a different length. There's one of length 300, the same as our original data set. There are two elements of length 3 (`withinss` and `tot.withinss`) and `centers` is a matrix with 3 rows. And then there are the elements of length 1: `totss`, `tot.withinss`, `betweenss`, and `iter`. (The value `ifault` indicates possible algorithm problems.)

These differing lengths have important meaning when we want to tidy our data set; they signify that each type of component communicates a *different kind* of information.

- `cluster` (300 values) contains information about each *point*
- `centers`, `withinss`, and `size` (3 values) contain information about each *cluster*
- `totss`, `tot.withinss`, `betweenss`, and `iter` (1 value) contain information about the *full clustering*

Which of these do we want to extract? There is no right answer; each of them may be interesting to an analyst. Because they communicate entirely different information (not to mention there's no straightforward way to combine them), they are extracted by separate functions. `augment` adds the point classifications to the original data set:


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

The `tidy()` function summarizes on a per-cluster level:


```r
tidy(kclust)
#> # A tibble: 3 × 5
#>        x1    x2  size withinss cluster
#>     <dbl> <dbl> <int>    <dbl> <fct>  
#> 1  0.0885  1.05   148     299. 1      
#> 2 -3.14   -2.00    51     109. 2      
#> 3  5.00   -1.05   101     243. 3
```

And as it always does, the `glance()` function extracts a single-row summary:


```r
glance(kclust)
#> # A tibble: 1 × 4
#>   totss tot.withinss betweenss  iter
#>   <dbl>        <dbl>     <dbl> <int>
#> 1 3724.         651.     3073.     2
```

## Exploratory clustering

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
#> 
#> [1] /Library/Frameworks/R.framework/Versions/4.0/Resources/library
```

