---
title: "resampling 으로 모델 평가하기"
weight: 3
tags: [rsample, parsnip, tune, workflows, yardstick]
categories: [resampling]
description: | 
  Measure model performance by generating different versions of the training data through resampling.
---
<script src="{{< blogdown/postref >}}index_files/kePrint/kePrint.js"></script>
<link href="{{< blogdown/postref >}}index_files/lightable/lightable.css" rel="stylesheet" />







## 들어가기 {#intro}

지금까지 [모델을 만들고](/start/models/) [recipe 로 데이터 전처리](/start/recipes/) 를 하였습니다. 또한 [parsnip 모델](https://tidymodels.github.io/parsnip/) 과 [recipe](https://tidymodels.github.io/recipes/) 을 묶는 방법으로 [ 워크플로](/start/recipes/#fit-workflow) 를 살펴보았습니다. 트레인된 모델이 있다면, 이 모델이 새로운 데이터에 예측을 얼마나 잘 하는지를 측정할 방법이 필요합니다. 이 튜토리얼에서는 **resampling** 통계량에 기반하여 모델 성능을 정의하는 법을 설명합니다.

To use code in this article,  you will need to install the following packages: modeldata, ranger, and tidymodels.


```r
library(tidymodels) # for the rsample package, along with the rest of tidymodels

# Helper packages
library(modeldata)  # for the cells data
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 세포 이미지 데이터 {#data}

[modeldata 패키지](https://cran.r-project.org/web/packages/modeldata/index.html) 에 있는 [Hill, LaPan, Li, and Haney (2007)](http://www.biomedcentral.com/1471-2105/8/340) 데이터를 사용하여, resampling 으로 세포 이미지 세그멘테이션 품질을 예측해 봅시다. 이 데이터를 R 에 로드합니다:


```r
data(cells, package = "modeldata")
cells
#> # A tibble: 2,019 × 58
#>   case  class angle_ch_1 area_ch_1 avg_inten_ch_1 avg_inten_ch_2 avg_inten_ch_3
#>   <fct> <fct>      <dbl>     <int>          <dbl>          <dbl>          <dbl>
#> 1 Test  PS        143.         185           15.7           4.95           9.55
#> 2 Train PS        134.         819           31.9         207.            69.9 
#> 3 Train WS        107.         431           28.0         116.            63.9 
#> 4 Train PS         69.2        298           19.5         102.            28.2 
#> 5 Test  PS          2.89       285           24.3         112.            20.5 
#> # … with 2,014 more rows, and 51 more variables: avg_inten_ch_4 <dbl>,
#> #   convex_hull_area_ratio_ch_1 <dbl>, convex_hull_perim_ratio_ch_1 <dbl>,
#> #   diff_inten_density_ch_1 <dbl>, diff_inten_density_ch_3 <dbl>, …
```

We have data for 2019 cells, with 58 variables. The main outcome variable of interest for us here is called `class`, which you can see is a factor. But before we jump into predicting the `class` variable, we need to understand it better. Below is a brief primer on cell image segmentation.

### Predicting image segmentation quality

Some biologists conduct experiments on cells. In drug discovery, a particular type of cell can be treated with either a drug or control and then observed to see what the effect is (if any). A common approach for this kind of measurement is cell imaging. Different parts of the cells can be colored so that the locations of a cell can be determined. 

For example, in top panel of this image of five cells, the green color is meant to define the boundary of the cell (coloring something called the cytoskeleton) while the blue color defines the nucleus of the cell. 

<img src="img/cells.png" width="70%" style="display: block; margin: auto;" />

Using these colors, the cells in an image can be _segmented_ so that we know which pixels belong to which cell. If this is done well, the cell can be measured in different ways that are important to the biology. Sometimes the shape of the cell matters and different mathematical tools are used to summarize characteristics like the size or "oblongness" of the cell. 

The bottom panel shows some segmentation results. Cells 1 and 5 are fairly well segmented. However, cells 2 to 4 are bunched up together because the segmentation was not very good. The consequence of bad segmentation is data contamination; when the biologist analyzes the shape or size of these cells, the data are inaccurate and could lead to the wrong conclusion. 

A cell-based experiment might involve millions of cells so it is unfeasible to visually assess them all. Instead, a subsample can be created and these cells can be manually labeled by experts as either poorly segmented (`PS`) or well-segmented (`WS`). If we can predict these labels accurately, the larger data set can be improved by filtering out the cells most likely to be poorly segmented.

### Back to the cells data

The `cells` data has `class` labels for 2019 cells &mdash; each cell is labeled as either poorly segmented (`PS`) or well-segmented (`WS`). Each also has a total of 56 predictors based on automated image analysis measurements. For example, `avg_inten_ch_1` is the mean intensity of the data contained in the nucleus, `area_ch_1` is the total size of the cell, and so on (some predictors are fairly arcane in nature). 


```r
cells
#> # A tibble: 2,019 × 58
#>   case  class angle_ch_1 area_ch_1 avg_inten_ch_1 avg_inten_ch_2 avg_inten_ch_3
#>   <fct> <fct>      <dbl>     <int>          <dbl>          <dbl>          <dbl>
#> 1 Test  PS        143.         185           15.7           4.95           9.55
#> 2 Train PS        134.         819           31.9         207.            69.9 
#> 3 Train WS        107.         431           28.0         116.            63.9 
#> 4 Train PS         69.2        298           19.5         102.            28.2 
#> 5 Test  PS          2.89       285           24.3         112.            20.5 
#> # … with 2,014 more rows, and 51 more variables: avg_inten_ch_4 <dbl>,
#> #   convex_hull_area_ratio_ch_1 <dbl>, convex_hull_perim_ratio_ch_1 <dbl>,
#> #   diff_inten_density_ch_1 <dbl>, diff_inten_density_ch_3 <dbl>, …
```

The rates of the classes are somewhat imbalanced; there are more poorly segmented cells than well-segmented cells:


```r
cells %>% 
  count(class) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   class     n  prop
#>   <fct> <int> <dbl>
#> 1 PS     1300 0.644
#> 2 WS      719 0.356
```

## 데이터 나누기 {#data-split}

In our previous [*Preprocess your data with recipes*](/start/recipes/#data-split) article, we started by splitting our data. It is common when beginning a modeling project to [separate the data set](https://bookdown.org/max/FES/data-splitting.html) into two partitions: 

 * The _training set_ is used to estimate parameters, compare models and feature engineering techniques, tune models, etc.

 * The _test set_ is held in reserve until the end of the project, at which point there should only be one or two models under serious consideration. It is used as an unbiased source for measuring final model performance. 

There are different ways to create these partitions of the data. The most common approach is to use a random sample. Suppose that one quarter of the data were reserved for the test set. Random sampling would randomly select 25% for the test set and use the remainder for the training set. We can use the [rsample](https://tidymodels.github.io/rsample/) package for this purpose. 

Since random sampling uses random numbers, it is important to set the random number seed. This ensures that the random numbers can be reproduced at a later time (if needed). 

The function `rsample::initial_split()` takes the original data and saves the information on how to make the partitions. In the original analysis, the authors made their own training/test set and that information is contained in the column `case`. To demonstrate how to make a split, we'll remove this column before we make our own split:


```r
set.seed(123)
cell_split <- initial_split(cells %>% select(-case), 
                            strata = class)
```

Here we used the [`strata` argument](https://tidymodels.github.io/rsample/reference/initial_split.html), which conducts a stratified split. This ensures that, despite the imbalance we noticed in our `class` variable, our training and test data sets will keep roughly the same proportions of poorly and well-segmented cells as in the original data. After the `initial_split`, the `training()` and `testing()` functions return the actual data sets. 


```r
cell_train <- training(cell_split)
cell_test  <- testing(cell_split)

nrow(cell_train)
#> [1] 1514
nrow(cell_train)/nrow(cells)
#> [1] 0.7498762

# training set proportions by class
cell_train %>% 
  count(class) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   class     n  prop
#>   <fct> <int> <dbl>
#> 1 PS      975 0.644
#> 2 WS      539 0.356

# test set proportions by class
cell_test %>% 
  count(class) %>% 
  mutate(prop = n/sum(n))
#> # A tibble: 2 × 3
#>   class     n  prop
#>   <fct> <int> <dbl>
#> 1 PS      325 0.644
#> 2 WS      180 0.356
```

The majority of the modeling work is then conducted on the training set data. 


## Modeling

[랜덤포레스트 모델](https://en.wikipedia.org/wiki/Random_forest) 은 [decision trees](https://en.wikipedia.org/wiki/Decision_tree) 의  [앙상블](https://en.wikipedia.org/wiki/Ensemble_learning) 입니다. 약간 다른 트레이닝 셋에 기반하여 많은 수의 decision tree 모델이 생성됩니다. 각 decision tree 가 생성될 때, 적합과정은 최대한 decision tree 들이 다양하게 되길 유도합니다. 트리의 집합은 랜덤포레스트 모델로 조합되고, 새로운 샘플이 예측될 때, 각 트리로 부터의 투표가 최종 예측값을 계산하는데 사용됩니다. 우리의 `cells` 예시 데이터의 `class` 와 같은 범주형 종속변수에 대해, 랜덤포레스트 의 모든 트리를 통틀어 가장 많은 투표를 받은 모델이 새로운 샘플의 예측 범주를 결정합니다. 

One of the benefits of a random forest model is that it is very low maintenance;  it requires very little preprocessing of the data and the default parameters tend to give reasonable results. For that reason, we won't create a recipe for the `cells` data.

At the same time, the number of trees in the ensemble should be large (in the thousands) and this makes the model moderately expensive to compute. 

To fit a random forest model on the training set, let's use the [parsnip](https://tidymodels.github.io/parsnip/) package with the [ranger](https://cran.r-project.org/web/packages/ranger/index.html) engine. We first define the model that we want to create:


```r
rf_mod <- 
  rand_forest(trees = 1000) %>% 
  set_engine("ranger") %>% 
  set_mode("classification")
```

Starting with this parsnip model object, the `fit()` function can be used with a model formula. Since random forest models use random numbers, we again set the seed prior to computing: 


```r
set.seed(234)
rf_fit <- 
  rf_mod %>% 
  fit(class ~ ., data = cell_train)
rf_fit
#> parsnip model object
#> 
#> Fit time:  3.8s 
#> Ranger result
#> 
#> Call:
#>  ranger::ranger(x = maybe_data_frame(x), y = y, num.trees = ~1000,      num.threads = 1, verbose = FALSE, seed = sample.int(10^5,          1), probability = TRUE) 
#> 
#> Type:                             Probability estimation 
#> Number of trees:                  1000 
#> Sample size:                      1514 
#> Number of independent variables:  56 
#> Mtry:                             7 
#> Target node size:                 10 
#> Variable importance mode:         none 
#> Splitrule:                        gini 
#> OOB prediction error (Brier s.):  0.1187479
```

This new `rf_fit` object is our fitted model, trained on our training data set. 


## 성능 추정하기 {#performance}

During a modeling project, we might create a variety of different models. To choose between them, we need to consider how well these models do, as measured by some performance statistics. In our example in this article, some options we could use are: 

 * the area under the Receiver Operating Characteristic (ROC) curve, and
 
 * overall classification accuracy.
 
The ROC curve uses the class probability estimates to give us a sense of performance across the entire set of potential probability cutoffs. Overall accuracy uses the hard class predictions to measure performance. The hard class predictions tell us whether our model predicted `PS` or `WS` for each cell. But, behind those predictions, the model is actually estimating a probability. A simple 50% probability cutoff is used to categorize a cell as poorly segmented.

[yardstick 패키지](https://tidymodels.github.io/yardstick/) 에는 이러한 두 측정값들을 계산하는 함수, `roc_auc()` 와 `accuracy()` 가 있습니다. 

At first glance, it might seem like a good idea to use the training set data to compute these statistics. (This is actually a very bad idea.) Let's see what happens if we try this. To evaluate performance based on the training set, we call the `predict()` method to get both types of predictions (i.e. probabilities and hard class predictions).


```r
rf_training_pred <- 
  predict(rf_fit, cell_train) %>% 
  bind_cols(predict(rf_fit, cell_train, type = "prob")) %>% 
  # Add the true outcome data back in
  bind_cols(cell_train %>% 
              select(class))
```

yardstick 함수들을 사용하여, 이 모델은 엄청난 결과를 보여주는데, 결과가 너무 엄청나서 의심되기 시작할 것입니다: 


```r
rf_training_pred %>%                # training set predictions
  roc_auc(truth = class, .pred_PS)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary          1.00
rf_training_pred %>%                # training set predictions
  accuracy(truth = class, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy binary         0.990
```

Now that we have this model with exceptional performance, we proceed to the test set. Unfortunately, we discover that, although our results aren't bad, they are certainly worse than what we initially thought based on predicting the training set: 


```r
rf_testing_pred <- 
  predict(rf_fit, cell_test) %>% 
  bind_cols(predict(rf_fit, cell_test, type = "prob")) %>% 
  bind_cols(cell_test %>% select(class))
```


```r
rf_testing_pred %>%                   # test set predictions
  roc_auc(truth = class, .pred_PS)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.891
rf_testing_pred %>%                   # test set predictions
  accuracy(truth = class, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy binary         0.814
```

### 무슨일이 일어난 거야?

There are several reasons why training set statistics like the ones shown in this section can be unrealistically optimistic: 

 * Models like random forests, neural networks, and other black-box methods can essentially memorize the training set. Re-predicting that same set should always result in nearly perfect results.

* The training set does not have the capacity to be a good arbiter of performance. It is not an independent piece of information; predicting the training set can only reflect what the model already knows. 

To understand that second point better, think about an analogy from teaching. Suppose you give a class a test, then give them the answers, then provide the same test. The student scores on the _second_ test do not accurately reflect what they know about the subject; these scores would probably be higher than their results on the first test. 



## Resampling 를 이용한 문제해결 {#resampling}

cross-validation 과 bootstrap 과 같은 resampling 방법은 실험적 시뮬레이션 시스템입니다. They create a series of data sets similar to the training/testing split discussed previously; a subset of the data are used for creating the model and a different subset is used to measure performance. Resampling is always used with the _training set_. This schematic from [Kuhn and Johnson (2019)](https://bookdown.org/max/FES/resampling.html) illustrates data usage for resampling methods:

<img src="img/resampling.svg" width="85%" style="display: block; margin: auto;" />

In the first level of this diagram, you see what happens when you use `rsample::initial_split()`, which splits the original data into training and test sets. Then, the training set is chosen for resampling, and the test set is held out.

Let's use 10-fold cross-validation (CV) in this example. This method randomly allocates the 1514 cells in the training set to 10 groups of roughly equal size, called "folds". For the first iteration of resampling, the first fold of about 151 cells are held out for the purpose of measuring performance. This is similar to a test set but, to avoid confusion, we call these data the _assessment set_ in the tidymodels framework. 

The other 90% of the data (about 1362 cells) are used to fit the model. Again, this sounds similar to a training set, so in tidymodels we call this data the _analysis set_. This model, trained on the analysis set, is applied to the assessment set to generate predictions, and performance statistics are computed based on those predictions. 

In this example, 10-fold CV moves iteratively through the folds and leaves a different 10% out each time for model assessment. At the end of this process, there are 10 sets of performance statistics that were created on 10 data sets that were not used in the modeling process. For the cell example, this means 10 accuracies and 10 areas under the ROC curve. While 10 models were created, these are not used further; we do not keep the models themselves trained on these folds because their only purpose is calculating performance metrics. 



The final resampling estimates for the model are the **averages** of the performance statistics replicates. For example, suppose for our data the results were: 

<table class="table" style="width: auto !important; margin-left: auto; margin-right: auto;">
 <thead>
  <tr>
   <th style="text-align:left;"> resample </th>
   <th style="text-align:right;"> accuracy </th>
   <th style="text-align:right;"> roc_auc </th>
   <th style="text-align:right;"> assessment size </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> Fold01 </td>
   <td style="text-align:right;"> 0.8223684 </td>
   <td style="text-align:right;"> 0.8922717 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold02 </td>
   <td style="text-align:right;"> 0.7828947 </td>
   <td style="text-align:right;"> 0.8744543 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold03 </td>
   <td style="text-align:right;"> 0.8486842 </td>
   <td style="text-align:right;"> 0.9044846 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold04 </td>
   <td style="text-align:right;"> 0.8421053 </td>
   <td style="text-align:right;"> 0.8920151 </td>
   <td style="text-align:right;"> 152 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold05 </td>
   <td style="text-align:right;"> 0.7947020 </td>
   <td style="text-align:right;"> 0.8827797 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold06 </td>
   <td style="text-align:right;"> 0.8543046 </td>
   <td style="text-align:right;"> 0.9271222 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold07 </td>
   <td style="text-align:right;"> 0.8145695 </td>
   <td style="text-align:right;"> 0.9000770 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold08 </td>
   <td style="text-align:right;"> 0.8543046 </td>
   <td style="text-align:right;"> 0.9265734 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold09 </td>
   <td style="text-align:right;"> 0.8543046 </td>
   <td style="text-align:right;"> 0.9219256 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> Fold10 </td>
   <td style="text-align:right;"> 0.8609272 </td>
   <td style="text-align:right;"> 0.9276316 </td>
   <td style="text-align:right;"> 151 </td>
  </tr>
</tbody>
</table>

From these resampling statistics, the final estimate of performance for this random forest model would be 0.905 for the area under the ROC curve and 0.833 for accuracy. 

These resampling statistics are an effective method for measuring model performance _without_ predicting the training set directly as a whole. 

## Fit a model with resampling {#fit-resamples}

To generate these results, the first step is to create a resampling object using rsample. There are [several resampling methods](https://tidymodels.github.io/rsample/reference/index.html#section-resampling-methods) implemented in rsample; cross-validation folds can be created using `vfold_cv()`: 


```r
set.seed(345)
folds <- vfold_cv(cell_train, v = 10)
folds
#> #  10-fold cross-validation 
#> # A tibble: 10 × 2
#>    splits             id    
#>    <list>             <chr> 
#>  1 <split [1362/152]> Fold01
#>  2 <split [1362/152]> Fold02
#>  3 <split [1362/152]> Fold03
#>  4 <split [1362/152]> Fold04
#>  5 <split [1363/151]> Fold05
#>  6 <split [1363/151]> Fold06
#>  7 <split [1363/151]> Fold07
#>  8 <split [1363/151]> Fold08
#>  9 <split [1363/151]> Fold09
#> 10 <split [1363/151]> Fold10
```

The list column for `splits` contains the information on which rows belong in the analysis and assessment sets. There are functions that can be used to extract the individual resampled data called `analysis()` and `assessment()`. 

However, the tune package contains high-level functions that can do the required computations to resample a model for the purpose of measuring performance. You have several options for building an object for resampling:

+ Resample a model specification preprocessed with a formula or [recipe](/start/recipes/), or 

+ Resample a [`workflow()`](https://tidymodels.github.io/workflows/) that bundles together a model specification and formula/recipe. 

For this example, let's use a `workflow()` that bundles together the random forest model and a formula, since we are not using a recipe. Whichever of these options you use, the syntax to `fit_resamples()` is very similar to `fit()`: 


```r
rf_wf <- 
  workflow() %>%
  add_model(rf_mod) %>%
  add_formula(class ~ .)

set.seed(456)
rf_fit_rs <- 
  rf_wf %>% 
  fit_resamples(folds)
```


```r
rf_fit_rs
#> # Resampling results
#> # 10-fold cross-validation 
#> # A tibble: 10 × 4
#>    splits             id     .metrics         .notes          
#>    <list>             <chr>  <list>           <list>          
#>  1 <split [1362/152]> Fold01 <tibble [2 × 4]> <tibble [0 × 1]>
#>  2 <split [1362/152]> Fold02 <tibble [2 × 4]> <tibble [0 × 1]>
#>  3 <split [1362/152]> Fold03 <tibble [2 × 4]> <tibble [0 × 1]>
#>  4 <split [1362/152]> Fold04 <tibble [2 × 4]> <tibble [0 × 1]>
#>  5 <split [1363/151]> Fold05 <tibble [2 × 4]> <tibble [0 × 1]>
#>  6 <split [1363/151]> Fold06 <tibble [2 × 4]> <tibble [0 × 1]>
#>  7 <split [1363/151]> Fold07 <tibble [2 × 4]> <tibble [0 × 1]>
#>  8 <split [1363/151]> Fold08 <tibble [2 × 4]> <tibble [0 × 1]>
#>  9 <split [1363/151]> Fold09 <tibble [2 × 4]> <tibble [0 × 1]>
#> 10 <split [1363/151]> Fold10 <tibble [2 × 4]> <tibble [0 × 1]>
```

The results are similar to the `folds` results with some extra columns. The column `.metrics` contains the performance statistics created from the 10 assessment sets. These can be manually unnested but the tune package contains a number of simple functions that can extract these data: 
 

```r
collect_metrics(rf_fit_rs)
#> # A tibble: 2 × 6
#>   .metric  .estimator  mean     n std_err .config             
#>   <chr>    <chr>      <dbl> <int>   <dbl> <chr>               
#> 1 accuracy binary     0.833    10 0.00876 Preprocessor1_Model1
#> 2 roc_auc  binary     0.905    10 0.00627 Preprocessor1_Model1
```

Think about these values we now have for accuracy and AUC. These performance metrics are now more realistic (i.e. lower) than our ill-advised first attempt at computing performance metrics in the section above. If we wanted to try different model types for this data set, we could more confidently compare performance metrics computed using resampling to choose between models. Also, remember that at the end of our project, we return to our test set to estimate final model performance. We have looked at this once already before we started using resampling, but let's remind ourselves of the results:


```r
rf_testing_pred %>%                   # test set predictions
  roc_auc(truth = class, .pred_PS)
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 roc_auc binary         0.891
rf_testing_pred %>%                   # test set predictions
  accuracy(truth = class, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy binary         0.814
```

The performance metrics from the test set are much closer to the performance metrics computed using resampling than our first ("bad idea") attempt. Resampling allows us to simulate how well our model will perform on new data, and the test set acts as the final, unbiased check for our model's performance.



## Session information


```
#> ─ Session info ───────────────────────────────────────────────────────────────
#>  setting  value                       
#>  version  R version 4.1.1 (2021-08-10)
#>  os       Ubuntu 18.04.5 LTS          
#>  system   x86_64, linux-gnu           
#>  ui       X11                         
#>  language (EN)                        
#>  collate  C.UTF-8                     
#>  ctype    C.UTF-8                     
#>  tz       Etc/UTC                     
#>  date     2021-10-25                  
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package    * version date       lib source        
#>  broom      * 0.7.9   2021-07-27 [1] CRAN (R 4.1.1)
#>  dials      * 0.0.10  2021-09-10 [1] CRAN (R 4.1.1)
#>  dplyr      * 1.0.7   2021-06-18 [1] CRAN (R 4.1.1)
#>  ggplot2    * 3.3.5   2021-06-25 [1] CRAN (R 4.1.0)
#>  infer      * 1.0.0   2021-08-13 [1] CRAN (R 4.1.1)
#>  modeldata  * 0.1.1   2021-07-14 [1] CRAN (R 4.1.1)
#>  parsnip    * 0.1.7   2021-07-21 [1] CRAN (R 4.1.1)
#>  purrr      * 0.3.4   2020-04-17 [1] CRAN (R 4.1.0)
#>  ranger     * 0.13.1  2021-07-14 [1] CRAN (R 4.1.1)
#>  recipes    * 0.1.17  2021-09-27 [1] CRAN (R 4.1.1)
#>  rlang      * 0.4.11  2021-04-30 [1] CRAN (R 4.1.0)
#>  rsample    * 0.1.0   2021-05-08 [1] CRAN (R 4.1.1)
#>  tibble     * 3.1.5   2021-09-30 [1] CRAN (R 4.1.1)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.1.1)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.1.1)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.1.1)
#>  yardstick  * 0.0.8   2021-03-28 [1] CRAN (R 4.1.1)
#> 
#> [1] /usr/local/lib/R/site-library
#> [2] /usr/lib/R/site-library
#> [3] /usr/lib/R/library
```
