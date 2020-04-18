---
title: "Effect encodings for categorical predictors"
tags: [embed, recipes]
categories: [model fittings]
type: learn-subsection
weight: 2
description: | 
  Encode categorical predictors with many levels into a single numeric column.
---


  


# Introduction

To use the code in this article, you will need to install the following packages: embed, ggrepel, modeldata, rstanarm, and tidymodels.

Many types of models require the predictor data to be represented as numbers. When the predictor represents a category, the most common method to encode that data into a numeric format is to make _dummy variables_. For example, with the iris data, if the species were a predictor, the three types of flowers would be represented by two new numeric columns:

<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
<tr>
<th style="border-bottom:hidden" colspan="1"></th>
<th style="border-bottom:hidden; padding-bottom:0; padding-left:3px;padding-right:3px;text-align: center; " colspan="2"><div style="border-bottom: 1px solid #ddd; padding-bottom: 5px; ">Dummy Variables</div></th>
</tr>
  <tr>
   <th style="text-align:left;"> Species </th>
   <th style="text-align:right;"> versicolor </th>
   <th style="text-align:right;"> virginica </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> setosa </td>
   <td style="text-align:right;"> 0 </td>
   <td style="text-align:right;"> 0 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> versicolor </td>
   <td style="text-align:right;"> 1 </td>
   <td style="text-align:right;"> 0 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> virginica </td>
   <td style="text-align:right;"> 0 </td>
   <td style="text-align:right;"> 1 </td>
  </tr>
</tbody>
</table>

One issue with this approach is that, for some predictors, the number of dummy variables could be very large and these predictors would be very sparse (i.e., mostly zero). 

An alternative of dummy encodings, a different encoding that takes the outcome data into account. _Effect_ or _Likelihood Encoding_ can be used. This method replaces the original factor column with a single numeric column that represents the effect of the categories on the outcome. 

For the iris data, suppose the sepal length were being predicted. The simplest approach for an effect encoding would be to replace each category with the _mean outcome value_ for that group. That would result this encoding: 


<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
  <tr>
   <th style="text-align:left;"> Species </th>
   <th style="text-align:right;"> Effect </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> setosa </td>
   <td style="text-align:right;"> 5.01 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> versicolor </td>
   <td style="text-align:right;"> 5.94 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> virginica </td>
   <td style="text-align:right;"> 6.59 </td>
  </tr>
</tbody>
</table>

However, there are different ways of estimate these values for different data sets, especially situations where some of the categories have very few values in the training set.  The article discussed different methods for estimating the effects and how to use this encoding method within a recipe. 

# Generalized linear models

Generalized linear models include linear and logistic regression. These models can be used to create the encodings, depending on the type of outcome type. 

The example used here is the OkCupid data from [Kim and Escobedo-Land (2015)(pdf)](http://www.amstat.org/publications/jse/v23n2/kim.pdf). In [Kuhn and Johnson (2018)](http://feat.engineering), these data are used to predict whether a person is in the STEM fields (science, technology, engineering, and mathematics). One predictor, geographic location, is a factor variable. The frequencies of different locations vary between 1 person and 31064 people. There are 135 locations in the data. Rather than producing 134 indicator variables for a model, a single numeric variable can be used to represent the _effect_ or _impact_ of the factor level on the outcome. In this case, where a factor outcome is being predicted (STEM or not), the effects are quantified by the log-odds of the location for being STEM. 

To start, a split of the original data into training and test sets is created:


```r
library(tidymodels)
library(embed)

data(okc, package = "modeldata")

# Make a training/test split
set.seed(2642)
split <- initial_split(okc, prop = 1/2)
okc_tr <- training(split)
okc_te <-  testing(split)
```

The simplest approach is to compute the raw log-odds for each location using the raw training set frequencies. 


```r
props <- 
  okc_tr %>%
  group_by(location) %>%
  summarise(
    prop = mean(Class == "stem"),
    log_odds  = log(prop/(1-prop)),
    n = length(Class)
  )
props 
#> # A tibble: 103 x 4
#>    location            prop log_odds     n
#>    <chr>              <dbl>    <dbl> <int>
#>  1 alameda           0.164     -1.63   446
#>  2 albany            0.120     -1.99   108
#>  3 ashland           0       -Inf        1
#>  4 atherton          0.0952    -2.25    21
#>  5 bayshore          0       -Inf        1
#>  6 belmont           0.209     -1.33   134
#>  7 belvedere tiburon 0.154     -1.70    26
#>  8 benicia           0.0673    -2.63   104
#>  9 berkeley          0.130     -1.90  2143
#> 10 bolinas           0       -Inf        1
#> # … with 93 more rows
```

This approach is not very effective since the locations with a single observed values have infinite log-odds. 

In subsequent sections, a logistic regression model is used. When the outcome variable is numeric, the steps automatically use linear regression models to estimate effects (as was shown with the iris data in the introduction).

Even within generalized linear models, there are some different estimation techniques that can be used. The main equation is how each of the locations affect the estimates. In the raw estimates shown above, only the data within a location are used to estimate that effect. The locations are not pooled in any way. However, there are some statistical techniques that can leverage all of the data to create the location-specific effects. 

Now let's consider using logistic regression to produce the estimates without pooling.In this case, an ordinary generalized linear model is used to estimate the effects using the `step_lencode_glm()` function in the embed package:


```r
okc_glm <- 
  recipe(Class ~ ., data = okc_tr) %>%
  # Specify the variable being encoded and the outcome
  step_lencode_glm(location, outcome = vars(Class)) %>%
  # Estimate the effects
  prep()
```

The `tidy()` method can be used to extract the encodings and are merged with the raw estimates:


```r
glm_estimates <- 
  tidy(okc_glm, number = 1) %>% 
  select(-terms, -id) 
glm_estimates
#> # A tibble: 104 x 2
#>    level              value
#>    <chr>              <dbl>
#>  1 alameda            -1.63
#>  2 albany             -1.99
#>  3 ashland           -14.6 
#>  4 atherton           -2.25
#>  5 bayshore          -14.6 
#>  6 belmont            -1.33
#>  7 belvedere tiburon  -1.70
#>  8 benicia            -2.63
#>  9 berkeley           -1.90
#> 10 bolinas           -14.6 
#> # … with 94 more rows

# How do they compare to the raw log-odds?
glm_estimates <- 
  glm_estimates %>%
  set_names(c("location", "no_pooling")) %>%
    inner_join(props, by = "location") 
```

The locations with a single value in the training set have large negative numbers which is the logistic regression model attempting to approximate `1/0`. For the locations with `n > 1`, the model estimates are effectively the same as the raw statistics:


```r
glm_estimates %>%
  filter(is.finite(log_odds)) %>%
  mutate(difference = log_odds - no_pooling) %>%
  select(difference) %>%
  summary()
#>    difference       
#>  Min.   :-9.17e-14  
#>  1st Qu.:-2.90e-15  
#>  Median :-4.00e-16  
#>  Mean   :-7.00e-16  
#>  3rd Qu.: 1.30e-15  
#>  Max.   : 6.55e-14
```

Note that there is also a effect that is used for a novel location for future data sets that is the average effect:


```r
tidy(okc_glm, number = 1) %>%
  filter(level == "..new") %>%
  select(-id)
#> # A tibble: 1 x 3
#>   level value terms   
#>   <chr> <dbl> <chr>   
#> 1 ..new -6.25 location
```

This is the value that would be used when new data being predicted come from a new factor level (that was not in the training set). 

## Partial pooling

Partial pooling methods estimate the effects by using all of the locations at once using a [hierarchical model](https://en.wikipedia.org/wiki/Multilevel_model). The locations are treated as a random set that contributes a random intercept to the previously used logistic regression. Before modeling, the distribution that is assumed for these random effects is called the _prior distribution_. 

Partial pooling estimates each effect as a combination of the individual empirical estimates of the log-odds and the prior distribution. For locations with small sample sizes, the final estimate is _shrunken_ towards the overall mean of the log-odds. This makes sense since we have poor information for estimating these locations. For locations with many data points, the estimates reply more on the empirical estimates. [This page](https://cran.r-project.org/web/packages/rstanarm/vignettes/pooling.html) has a good discussion of pooling using Bayesian models. 
 
One approach to _partial pooling_ is the function `step_lencode_bayes()` uses the `stan_glmer()` function in the rstanarm package. There are a number of options that can be used to control the model estimation routine, including:


```r
library(rstanarm)

opts <- 
  list(
    ## The number of chains
    chains = 2,
    ## How many cores to use 
    cores = 2,
    ## The total number of iterations per chain. 
    ## For time, this is set very low
    iter = 500,
    ## Set the random number seed
    seed = 8779,
    ## Stop logging of results
    refresh = 0,
    ## Use a non-standard prior
    prior_intercept = student_t(df = 1)
  )
```

The model is estimated via:




```r
library(embed)

okc_glmer <- 
  recipe(Class ~ ., data = okc_tr) %>%
  step_lencode_bayes(location, outcome = vars(Class), options = opts) %>% 
  prep()
```

This took more time (2.1 min) than the simple non-pooled model. The embeddings are extracted in the same way:


```r
all_estimates <- 
  tidy(okc_glmer, number = 1) %>% 
  select(-terms, -id) %>%
  set_names(c("location", "partial_pooling")) %>%
  inner_join(glm_estimates, by = "location")

all_estimates %>% 
  select(location, n, log_odds, no_pooling, partial_pooling)
#> # A tibble: 103 x 5
#>    location              n log_odds no_pooling partial_pooling
#>    <chr>             <int>    <dbl>      <dbl>           <dbl>
#>  1 alameda             446    -1.63      -1.63           -1.66
#>  2 albany              108    -1.99      -1.99           -1.99
#>  3 ashland               1  -Inf        -14.6            -1.98
#>  4 atherton             21    -2.25      -2.25           -2.06
#>  5 bayshore              1  -Inf        -14.6            -1.94
#>  6 belmont             134    -1.33      -1.33           -1.42
#>  7 belvedere tiburon    26    -1.70      -1.70           -1.86
#>  8 benicia             104    -2.63      -2.63           -2.40
#>  9 berkeley           2143    -1.90      -1.90           -1.90
#> 10 bolinas               1  -Inf        -14.6            -1.97
#> # … with 93 more rows
```

Note that the `n = 1` locations have estimates that are less extreme that the naive estimates. Also, 

Let's see the effect of the shrinkage that was induced by partial pooling by plotting the naive results versus the new results (finite data only). We'll highlight a few locations that show meaningful differences in the methods:


```r
library(ggrepel)

# Create a label column that will highlight these locations: 
cities <- c("santa cruz", "el sobrante", "san anselmo", 
            'west oakland', 'mountain view')
all_estimates <- 
  all_estimates %>% 
  mutate(
    label = paste0(gsub("_", " ", location), "\n(n=", n, ")"),
    label = ifelse(location %in% cities, label, "")
  )

rng <- extendrange(props$log_odds[is.finite(props$log_odds)], f = 0.1)

all_estimates %>%
  filter(is.finite(log_odds)) %>%
  ggplot(aes(x = log_odds, y = partial_pooling)) + 
  geom_abline(col = "red", alpha = .5) + 
  geom_point(aes(size = sqrt(n)), alpha = .5) +
  geom_text_repel(aes(label = label), size = 3) +
  xlim(rng) + ylim(rng) + 
  coord_equal()
```

<img src="figs/stan-compare-1.svg" width="80%" />

Notice that a few locations with a handful of instances have some of the more extreme effect estimates (e.g., Santa Cruz and West Oakland). Partial pooling pulled them closer to the mean log-odds over all the locations. In contrast is Mountain View which, unsurprisingly, had a high rate of STEM professions and a large log-odds. Its effect estimate under partial pooling (-0.319) was only slightly shrunken away from the raw estimate (-0.19). This is due to the sample size from this location (n = 190) being large enough that the prior distribution had less influence relative to the observed data.  

For partial pooling, any new levels are encoded with this value:


```r
tidy(okc_glmer, number = 1) %>%
  filter(level == "..new") %>%
  select(-terms, -id)
#> # A tibble: 1 x 2
#>   level value
#>   <chr> <dbl>
#> 1 ..new -1.95
```

The same generalized linear model can be fit using [mixed effect models](https://en.wikipedia.org/wiki/Mixed_model) via a random intercept whose distribution is constrained to be Gaussian. The lme4 package can also be used to get partially pooled estimates via `step_lencode_mixed()`.




```r
okc_mixed <- 
  recipe(Class ~ ., data = okc_tr) %>%
  step_lencode_mixed(location, outcome = vars(Class)) %>% 
  prep()

all_estimates <- 
  tidy(okc_mixed, number = 1) %>% 
  select(-terms, -id) %>%
  set_names(c("location", "mixed")) %>%
    inner_join(all_estimates, by = "location")
all_estimates %>% 
  select(location, log_odds, glm, partial_pooling, mixed)
```

Comparing the raw and mixed model estimates:


```r
all_estimates %>%
  filter(is.finite(log_odds)) %>%
  ggplot(aes(x = log_odds, y = mixed)) + 
  geom_abline(col = "red", alpha = .5) + 
  geom_point(aes(size = sqrt(n)), alpha = .5) +
  geom_text_repel(aes(label = label), size = 3) +
  xlim(rng) + ylim(rng) + 
  coord_equal()
```

<img src="figs/mixed-compare-1.svg" width="80%" />

These values are very similar to the Bayesian estimates but this method took a fraction of the time to fit (1.2 sec). 
 

## Session information


```
#> ─ Session info ───────────────────────────────────────────────────────────────
#>  setting  value                       
#>  version  R version 3.6.1 (2019-07-05)
#>  os       macOS Mojave 10.14.6        
#>  system   x86_64, darwin15.6.0        
#>  ui       X11                         
#>  language (EN)                        
#>  collate  en_US.UTF-8                 
#>  ctype    en_US.UTF-8                 
#>  tz       America/New_York            
#>  date     2020-04-17                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package    * version date       lib source        
#>  broom      * 0.5.4   2020-01-27 [1] CRAN (R 3.6.0)
#>  dials      * 0.0.6   2020-04-03 [1] CRAN (R 3.6.1)
#>  dplyr      * 0.8.5   2020-03-07 [1] CRAN (R 3.6.0)
#>  embed      * 0.0.6   2020-03-17 [1] CRAN (R 3.6.1)
#>  ggplot2    * 3.3.0   2020-03-05 [1] CRAN (R 3.6.0)
#>  ggrepel    * 0.8.2   2020-03-08 [1] CRAN (R 3.6.0)
#>  infer      * 0.5.1   2019-11-19 [1] CRAN (R 3.6.0)
#>  modeldata  * 0.0.1   2019-12-06 [1] CRAN (R 3.6.1)
#>  parsnip    * 0.1.0   2020-04-09 [1] CRAN (R 3.6.1)
#>  purrr      * 0.3.3   2019-10-18 [1] CRAN (R 3.6.0)
#>  recipes    * 0.1.10  2020-03-18 [1] CRAN (R 3.6.0)
#>  rlang        0.4.5   2020-03-01 [1] CRAN (R 3.6.0)
#>  rsample    * 0.0.6   2020-03-31 [1] CRAN (R 3.6.2)
#>  rstanarm   * 2.19.2  2019-10-03 [1] CRAN (R 3.6.1)
#>  tibble     * 2.1.3   2019-06-06 [1] CRAN (R 3.6.1)
#>  tidymodels * 0.1.0   2020-02-16 [1] CRAN (R 3.6.1)
#>  tune       * 0.1.0   2020-04-02 [1] CRAN (R 3.6.1)
#>  workflows  * 0.1.0   2019-12-30 [1] CRAN (R 3.6.1)
#>  yardstick  * 0.0.5   2020-01-23 [1] CRAN (R 3.6.0)
#> 
#> [1] /Library/Frameworks/R.framework/Versions/3.6/Resources/library
```
