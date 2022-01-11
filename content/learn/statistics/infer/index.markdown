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
+ `calculate()` 는 생성된 데이터로 부터 통계량의 분포를 계산하여 귀무 분포(null distribution)를 만듭니다.

이 vignette 에서, infer 에 있는 `gss` 데이터셋을 이용할 것인데, 이는 *General Social Survey* 의 11 개 변수를 가진 관측값 500 개의 샘플을 포함합니다.
Throughout this vignette, we make use of `gss`, a data set available in infer containing a sample of 500 observations of 11 variables from the *General Social Survey* 의 11 개 변수를 가진 관측값 500 개의 샘플을 포함한 . 


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

Each row is an individual survey response, containing some basic demographic information on the respondent as well as some additional variables. See `?gss` for more information on the variables included and their source. Note that this data (and our examples on it) are for demonstration purposes only, and will not necessarily provide accurate estimates unless weighted properly. For these examples, let's suppose that this data set is a representative sample of a population we want to learn about: American adults.

## Specify variables

The `specify()` function can be used to specify which of the variables in the data set you're interested in. If you're only interested in, say, the `age` of the respondents, you might write:


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

On the front end, the output of `specify()` just looks like it selects off the columns in the dataframe that you've specified. What do we see if we check the class of this object, though?


```r
gss %>%
  specify(response = age) %>%
  class()
#> [1] "infer"      "tbl_df"     "tbl"        "data.frame"
```

We can see that the infer class has been appended on top of the dataframe classes; this new class stores some extra metadata.

If you're interested in two variables (`age` and `partyid`, for example) you can `specify()` their relationship in one of two (equivalent) ways:


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

If you're doing inference on one proportion or a difference in proportions, you will need to use the `success` argument to specify which level of your `response` variable is a success. For instance, if you're interested in the proportion of the population with a college degree, you might use the following code:


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

## Declare the hypothesis

The next step in the infer pipeline is often to declare a null hypothesis using `hypothesize()`. The first step is to supply one of "independence" or "point" to the `null` argument. If your null hypothesis assumes independence between two variables, then this is all you need to supply to `hypothesize()`:


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

If you're doing inference on a point estimate, you will also need to provide one of `p` (the true proportion of successes, between 0 and 1), `mu` (the true mean), `med` (the true median), or `sigma` (the true standard deviation). For instance, if the null hypothesis is that the mean number of hours worked per week in our population is 40, we would write:


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

Again, from the front-end, the dataframe outputted from `hypothesize()` looks almost exactly the same as it did when it came out of `specify()`, but infer now "knows" your null hypothesis.

## Generate the distribution

Once we've asserted our null hypothesis using `hypothesize()`, we can construct a null distribution based on this hypothesis. We can do this using one of several methods, supplied in the `type` argument:

* `bootstrap`: A bootstrap sample will be drawn for each replicate, where a sample of size equal to the input sample size is drawn (with replacement) from the input sample data.  
* `permute`: For each replicate, each input value will be randomly reassigned (without replacement) to a new output value in the sample.  
* `simulate`: A value will be sampled from a theoretical distribution with parameters specified in `hypothesize()` for each replicate. (This option is currently only applicable for testing point estimates.)  

Continuing on with our example above, about the average number of hours worked a week, we might write:


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
#>  1         1  45.6
#>  2         1  38.6
#>  3         1  46.6
#>  4         1  58.6
#>  5         1  38.6
#>  6         1  38.6
#>  7         1  38.6
#>  8         1  38.6
#>  9         1  23.6
#> 10         1  38.6
#> # … with 2,499,990 more rows
```

In the above example, we take 5000 bootstrap samples to form our null distribution.

To generate a null distribution for the independence of two variables, we could also randomly reshuffle the pairings of explanatory and response variables to break any existing association. For instance, to generate 5000 replicates that can be used to create a null distribution under the assumption that political party affiliation is not affected by age:


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
#>  2 ind        34         1
#>  3 rep        24         1
#>  4 ind        42         1
#>  5 rep        31         1
#>  6 ind        32         1
#>  7 rep        48         1
#>  8 rep        36         1
#>  9 dem        30         1
#> 10 ind        33         1
#> # … with 2,499,990 more rows
```

## Calculate statistics

Depending on whether you're carrying out computation-based inference or theory-based inference, you will either supply `calculate()` with the output of `generate()` or `hypothesize()`, respectively. The function, for one, takes in a `stat` argument, which is currently one of `"mean"`, `"median"`, `"sum"`, `"sd"`, `"prop"`, `"count"`, `"diff in means"`, `"diff in medians"`, `"diff in props"`, `"Chisq"`, `"F"`, `"t"`, `"z"`, `"slope"`, or `"correlation"`. For example, continuing our example above to calculate the null distribution of mean hours worked per week:


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
#>  2         2  40.9
#>  3         3  40.6
#>  4         4  40.1
#>  5         5  39.3
#>  6         6  39.8
#>  7         7  40.8
#>  8         8  40.3
#>  9         9  40.1
#> 10        10  41.3
#> # … with 4,990 more rows
```

The output of `calculate()` here shows us the sample statistic (in this case, the mean) for each of our 1000 replicates. If you're carrying out inference on differences in means, medians, or proportions, or `\(t\)` and `\(z\)` statistics, you will need to supply an `order` argument, giving the order in which the explanatory variables should be subtracted. For instance, to find the difference in mean age of those that have a college degree and those that don't, we might write:


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
#>  1         1 -1.81 
#>  2         2 -0.655
#>  3         3 -0.540
#>  4         4 -2.18 
#>  5         5 -0.664
#>  6         6  2.54 
#>  7         7  0.535
#>  8         8  0.447
#>  9         9 -1.53 
#> 10        10  3.60 
#> # … with 4,990 more rows
```

## Other utilities

The infer package also offers several utilities to extract meaning out of summary statistics and null distributions; the package provides functions to visualize where a statistic is relative to a distribution (with `visualize()`), calculate p-values (with `get_p_value()`), and calculate confidence intervals (with `get_confidence_interval()`).

To illustrate, we'll go back to the example of determining whether the mean number of hours worked per week is 40 hours.


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

(Notice the warning: `Removed 1244 rows containing missing values.` This would be worth noting if you were actually carrying out this hypothesis test.)

Our point estimate 41.382 seems *pretty* close to 40, but a little bit different. We might wonder if this difference is just due to random chance, or if the mean number of hours worked per week in the population really isn't 40.

We could initially just visualize the null distribution.


```r
null_dist %>%
  visualize()
```

<img src="figs/visualize-1.svg" width="672" />

Where does our sample's observed statistic lie on this distribution? We can use the `obs_stat` argument to specify this.


```r
null_dist %>%
  visualize() +
  shade_p_value(obs_stat = point_estimate, direction = "two_sided")
```

<img src="figs/visualize2-1.svg" width="672" />

Notice that infer has also shaded the regions of the null distribution that are as (or more) extreme than our observed statistic. (Also, note that we now use the `+` operator to apply the `shade_p_value()` function. This is because `visualize()` outputs a plot object from ggplot2 instead of a dataframe, and the `+` operator is needed to add the p-value layer to the plot object.) The red bar looks like it's slightly far out on the right tail of the null distribution, so observing a sample mean of 41.382 hours would be somewhat unlikely if the mean was actually 40 hours. How unlikely, though?


```r
# get a two-tailed p-value
p_value <- null_dist %>%
  get_p_value(obs_stat = point_estimate, direction = "two_sided")

p_value
#> # A tibble: 1 × 1
#>   p_value
#>     <dbl>
#> 1  0.0372
```

It looks like the p-value is 0.037, which is pretty small---if the true mean number of hours worked per week was actually 40, the probability of our sample mean being this far (1.382 hours) from 40 would be 0.037. This may or may not be statistically significantly different, depending on the significance level `\(\alpha\)` you decided on *before* you ran this analysis. If you had set `\(\alpha = .05\)`, then this difference would be statistically significant, but if you had set `\(\alpha = .01\)`, then it would not be.

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
#> 1     40.1     42.7
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
#>  date     2022-01-11                  
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
 
