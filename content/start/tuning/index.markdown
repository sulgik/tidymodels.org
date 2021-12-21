---
title: "모델 파라미터 튜닝하기"
weight: 4
tags: [rsample, parsnip, tune, dials, workflows, yardstick]
categories: [tuning]
description: | 
  Estimate the best values for hyperparameters that cannot be learned directly during model training.
---






## 들어가기 {#intro}

모델 파라미터 중 어떤 것들은 모델 트레이닝 중 데이터셋으로 부터 직접 학습이 되지 않습니다. 이러한 파라미터를 **하이퍼파라미터** 라고 부릅니다. 트리 기반 모델에서 나누어지는 곳에서 샘플되는 설명변수의 숫자 (tidymodels 에서 `mtry` 로 부름) 혹은 부스티드 트리 모델에서 학습속도(`learn_rate` 로 부름) 가 하이퍼파라미터에 포함됩니다. 모델 트레이닝 중 하이퍼파라미터를 학습하는것 대신, 리샘플한 데이터셋에 많은 모형을 훈련하고 이 모델들의 성능을 탐색해서 가장 좋은 값을 _추정_ 할 수 있습니다. 이 프로세스를 **튜닝** 이라고 부릅니다.

하이퍼파라미터의 예로, 트리-기반 모델에서 쪼개짐에서 샘플된 설명변수의 숫자 (tidymodels 에서 `mtry` 라고 부름), 혹은 부스티드 트리모델에서 학습속도(`learning_rate` 이라고 부름)가 있습니다. 

이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: rpart, rpart.plot, tidymodels, and vip.


```r
library(tidymodels)  # for the tune package, along with the rest of tidymodels

# Helper packages
library(rpart.plot)  # for visualizing a decision tree
library(vip)         # for variable importance plots
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 세포 이미지 데이터, 계속 {#data}

이전의 [*리샘플링으로 모델 평가하기*](/start/resampling/) 장에서, 전문가들이 잘세그멘트됨(`WS`)과 잘못세그멘트됨(`PS`)로 라벨한 세포 이미지 데이터셋을 소개했었습니다. 잘/잘못 세그멘트된 이미지인지를 예측하기 위해 [랜덤포레스트모델](/start/resampling/#modeling)을 훈련해서 생물학자가 잘못 세그멘트된 세포이미지들을 분석에서 필터링하도록 했습니다. 여기서 이 데이터셋에 우리 모델의 성능을 추정하기 위해 [리샘플링](/start/resampling/#resampling)을 사용했었습니다.


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

## 이미지 세그멘테이션 예측하기, 더 정확히 {#why-tune}

랜덤포레스트 모델은 트리-기반 앙상블 방법이고 보통 [기본값 하이퍼파라미터](https://bradleyboehmke.github.io/HOML/random-forest.html#out-of-the-box-performance)로도 성능이 나쁘지 않습니다. 하지만, [boosted tree models](https://en.wikipedia.org/wiki/Gradient_boosting#Gradient_tree_boosting) or [decision tree models](https://en.wikipedia.org/wiki/Decision_tree) 같은 다른 트리기반 모델들은 정확도가 하이퍼파라미터 값들에 민감한 경우가 많습니다. 이 장에서 **decision tree** 모델을 트레이닝할 것입니다. decision tree 에는 튜닝할 수 있는 하이퍼파라미터 몇개가 있습니다. 한번 살펴봅시다:

- the complexity parameter (`cost_complexity` in tidymodels 에서 `cost_complexity` 라고 부름) for the tree, and
- the maximum `tree_depth`.

이러한 하이퍼파라미터를 튜닝하면 모델 성능을 개선할 수 있는데 decision tree 모델은 [overfitting](https://bookdown.org/max/FES/important-concepts.html#overfitting)되는 경향이 있기 때문입니다. 하나의 트리모델은 트레이닝 데이터에 _너무 잘_ 적합되는 경향이 있기 때문에 그렇습니다. &mdash; 사실 트레이닝 데이터에 존재하는 패턴들을 과학습해서 새로운 데이터를 예측할 때 방해가 될 정도가 됩니다.

과적합을 피하기 위해 모델 하이퍼파라미터를 튜닝할 것입니다. `cost_complexity` 의 값을 튜닝하면 우리 트리를  [pruning](https://bradleyboehmke.github.io/HOML/DT.html#pruning) 하여 도움이 됩니다. 더 복잡한 트리의 에러 레이트에 코스트 혹은 페널티를 추가합니다; 0에 가까운 코스트는 프룬된 트리노드 개수를 감소시키고 과적합된 나무를 제공하기 쉽습니다. 그러나 높은 코스트는 프룬된 트리 노드의 개수를 증가시키고 상반된 문제&mdash;an underfit tree 를 산출할 수 있습니다. 반면에 `tree_depth` 를 튜닝하면 우리 트리를 어떤 뎁스에 다다른 뒤 더 자라는 것을 [방지](https://bradleyboehmke.github.io/HOML/DT.html#early-stopping) 하는 도움을 줍니다. 우리의 목적은 이러한 하이퍼파라미터들을 튜닝하여 우리모델이 이미지 세그멘테이션을 가장 잘 예측하기 위한 값들로 튜닝하는 것입니다.

튜닝 프로세스를 시작하기 전에, 하이퍼파라미터 기본값으로 모델을 훈련시켰을 때와 같이 우리 데이터를 트레이닝셋과 테스트 셋으로 분리합니다. [전](/start/resampling/)과 같이 `strata = class` 를 하여 층화 샘플링을 이용하여 트레이닝과 테스팅 셋이 세그멘테이션 종류에 같은 비율이 되도록 합니다.


```r
set.seed(123)
cell_split <- initial_split(cells %>% select(-case), 
                            strata = class)
cell_train <- training(cell_split)
cell_test  <- testing(cell_split)
```

모델을 튜닝하기 위해 트레이닝 데이터를 사용합니다.

## 하이퍼파라미터 튜닝 {#tuning}

Let’s start with the parsnip package, using a [`decision_tree()`](https://parsnip.tidymodels.org/reference/decision_tree.html) model with the [rpart](https://cran.r-project.org/web/packages/rpart/index.html) engine. To tune the decision tree hyperparameters `cost_complexity` and `tree_depth`, we create a model specification that identifies which hyperparameters we plan to tune. 


```r
tune_spec <- 
  decision_tree(
    cost_complexity = tune(),
    tree_depth = tune()
  ) %>% 
  set_engine("rpart") %>% 
  set_mode("classification")

tune_spec
#> Decision Tree Model Specification (classification)
#> 
#> Main Arguments:
#>   cost_complexity = tune()
#>   tree_depth = tune()
#> 
#> Computational engine: rpart
```

Think of `tune()` here as a placeholder. After the tuning process, we will select a single numeric value for each of these hyperparameters. For now, we specify our parsnip model object and identify the hyperparameters we will `tune()`.

We can't train this specification on a single data set (such as the entire training set) and learn what the hyperparameter values should be, but we _can_ train many models using resampled data and see which models turn out best. We can create a regular grid of values to try using some convenience functions for each hyperparameter:


```r
tree_grid <- grid_regular(cost_complexity(),
                          tree_depth(),
                          levels = 5)
```

The function [`grid_regular()`](https://dials.tidymodels.org/reference/grid_regular.html) is from the [dials](https://dials.tidymodels.org/) package. It chooses sensible values to try for each hyperparameter; here, we asked for 5 of each. Since we have two to tune, `grid_regular()` returns 5 `\(\times\)` 5 = 25 different possible tuning combinations to try in a tidy tibble format.


```r
tree_grid
#> # A tibble: 25 × 2
#>    cost_complexity tree_depth
#>              <dbl>      <int>
#>  1    0.0000000001          1
#>  2    0.0000000178          1
#>  3    0.00000316            1
#>  4    0.000562              1
#>  5    0.1                   1
#>  6    0.0000000001          4
#>  7    0.0000000178          4
#>  8    0.00000316            4
#>  9    0.000562              4
#> 10    0.1                   4
#> # … with 15 more rows
```

Here, you can see all 5 values of `cost_complexity` ranging up to 0.1. These values get repeated for each of the 5 values of `tree_depth`:


```r
tree_grid %>% 
  count(tree_depth)
#> # A tibble: 5 × 2
#>   tree_depth     n
#>        <int> <int>
#> 1          1     5
#> 2          4     5
#> 3          8     5
#> 4         11     5
#> 5         15     5
```


Armed with our grid filled with 25 candidate decision tree models, let's create [cross-validation folds](/start/resampling/) for tuning:


```r
set.seed(234)
cell_folds <- vfold_cv(cell_train)
```

Tuning in tidymodels requires a resampled object created with the [rsample](https://rsample.tidymodels.org/) package.

## Model tuning with a grid {#tune-grid}

We are ready to tune! Let's use [`tune_grid()`](https://tune.tidymodels.org/reference/tune_grid.html) to fit models at all the different values we chose for each tuned hyperparameter. There are several options for building the object for tuning:

+ Tune a model specification along with a recipe or model, or 

+ Tune a [`workflow()`](https://workflows.tidymodels.org/) that bundles together a model specification and a recipe or model preprocessor. 

Here we use a `workflow()` with a straightforward formula; if this model required more involved data preprocessing, we could use `add_recipe()` instead of `add_formula()`.


```r
set.seed(345)

tree_wf <- workflow() %>%
  add_model(tune_spec) %>%
  add_formula(class ~ .)

tree_res <- 
  tree_wf %>% 
  tune_grid(
    resamples = cell_folds,
    grid = tree_grid
    )

tree_res
#> # Tuning results
#> # 10-fold cross-validation 
#> # A tibble: 10 × 4
#>    splits             id     .metrics          .notes          
#>    <list>             <chr>  <list>            <list>          
#>  1 <split [1362/152]> Fold01 <tibble [50 × 6]> <tibble [0 × 1]>
#>  2 <split [1362/152]> Fold02 <tibble [50 × 6]> <tibble [0 × 1]>
#>  3 <split [1362/152]> Fold03 <tibble [50 × 6]> <tibble [0 × 1]>
#>  4 <split [1362/152]> Fold04 <tibble [50 × 6]> <tibble [0 × 1]>
#>  5 <split [1363/151]> Fold05 <tibble [50 × 6]> <tibble [0 × 1]>
#>  6 <split [1363/151]> Fold06 <tibble [50 × 6]> <tibble [0 × 1]>
#>  7 <split [1363/151]> Fold07 <tibble [50 × 6]> <tibble [0 × 1]>
#>  8 <split [1363/151]> Fold08 <tibble [50 × 6]> <tibble [0 × 1]>
#>  9 <split [1363/151]> Fold09 <tibble [50 × 6]> <tibble [0 × 1]>
#> 10 <split [1363/151]> Fold10 <tibble [50 × 6]> <tibble [0 × 1]>
```

Once we have our tuning results, we can both explore them through visualization and then select the best result. The function `collect_metrics()` gives us a tidy tibble with all the results. We had 25 candidate models and two metrics, `accuracy` and `roc_auc`, and we get a row for each `.metric` and model. 


```r
tree_res %>% 
  collect_metrics()
#> # A tibble: 50 × 8
#>    cost_complexity tree_depth .metric  .estimator  mean     n std_err .config   
#>              <dbl>      <int> <chr>    <chr>      <dbl> <int>   <dbl> <chr>     
#>  1    0.0000000001          1 accuracy binary     0.732    10  0.0148 Preproces…
#>  2    0.0000000001          1 roc_auc  binary     0.777    10  0.0107 Preproces…
#>  3    0.0000000178          1 accuracy binary     0.732    10  0.0148 Preproces…
#>  4    0.0000000178          1 roc_auc  binary     0.777    10  0.0107 Preproces…
#>  5    0.00000316            1 accuracy binary     0.732    10  0.0148 Preproces…
#>  6    0.00000316            1 roc_auc  binary     0.777    10  0.0107 Preproces…
#>  7    0.000562              1 accuracy binary     0.732    10  0.0148 Preproces…
#>  8    0.000562              1 roc_auc  binary     0.777    10  0.0107 Preproces…
#>  9    0.1                   1 accuracy binary     0.732    10  0.0148 Preproces…
#> 10    0.1                   1 roc_auc  binary     0.777    10  0.0107 Preproces…
#> # … with 40 more rows
```

We might get more out of plotting these results:


```r
tree_res %>%
  collect_metrics() %>%
  mutate(tree_depth = factor(tree_depth)) %>%
  ggplot(aes(cost_complexity, mean, color = tree_depth)) +
  geom_line(size = 1.5, alpha = 0.6) +
  geom_point(size = 2) +
  facet_wrap(~ .metric, scales = "free", nrow = 2) +
  scale_x_log10(labels = scales::label_number()) +
  scale_color_viridis_d(option = "plasma", begin = .9, end = 0)
```

<img src="figs/best-tree-1.svg" width="768" />

We can see that our "stubbiest" tree, with a depth of 1, is the worst model according to both metrics and across all candidate values of `cost_complexity`. Our deepest tree, with a depth of 15, did better. However, the best tree seems to be between these values with a tree depth of 4. The [`show_best()`](https://tune.tidymodels.org/reference/show_best.html) function shows us the top 5 candidate models by default:


```r
tree_res %>%
  show_best("accuracy")
#> # A tibble: 5 × 8
#>   cost_complexity tree_depth .metric  .estimator  mean     n std_err .config    
#>             <dbl>      <int> <chr>    <chr>      <dbl> <int>   <dbl> <chr>      
#> 1    0.0000000001          4 accuracy binary     0.807    10  0.0119 Preprocess…
#> 2    0.0000000178          4 accuracy binary     0.807    10  0.0119 Preprocess…
#> 3    0.00000316            4 accuracy binary     0.807    10  0.0119 Preprocess…
#> 4    0.000562              4 accuracy binary     0.807    10  0.0119 Preprocess…
#> 5    0.1                   4 accuracy binary     0.786    10  0.0124 Preprocess…
```

We can also use the [`select_best()`](https://tune.tidymodels.org/reference/show_best.html) function to pull out the single set of hyperparameter values for our best decision tree model:


```r
best_tree <- tree_res %>%
  select_best("accuracy")

best_tree
#> # A tibble: 1 × 3
#>   cost_complexity tree_depth .config              
#>             <dbl>      <int> <chr>                
#> 1    0.0000000001          4 Preprocessor1_Model06
```

These are the values for `tree_depth` and `cost_complexity` that maximize accuracy in this data set of cell images. 


## Finalizing our model {#final-model}

We can update (or "finalize") our workflow object `tree_wf` with the values from `select_best()`. 


```r
final_wf <- 
  tree_wf %>% 
  finalize_workflow(best_tree)

final_wf
#> ══ Workflow ══════════════════════════════════════════════════════════
#> Preprocessor: Formula
#> Model: decision_tree()
#> 
#> ── Preprocessor ──────────────────────────────────────────────────────
#> class ~ .
#> 
#> ── Model ─────────────────────────────────────────────────────────────
#> Decision Tree Model Specification (classification)
#> 
#> Main Arguments:
#>   cost_complexity = 1e-10
#>   tree_depth = 4
#> 
#> Computational engine: rpart
```

Our tuning is done!

### The last fit

Finally, let's fit this final model to the training data and use our test data to estimate the model performance we expect to see with new data. We can use the function [`last_fit()`](https://tune.tidymodels.org/reference/last_fit.html) with our finalized model; this function _fits_ the finalized model on the full training data set and _evaluates_ the finalized model on the testing data.


```r
final_fit <- 
  final_wf %>%
  last_fit(cell_split) 

final_fit %>%
  collect_metrics()
#> # A tibble: 2 × 4
#>   .metric  .estimator .estimate .config             
#>   <chr>    <chr>          <dbl> <chr>               
#> 1 accuracy binary         0.802 Preprocessor1_Model1
#> 2 roc_auc  binary         0.840 Preprocessor1_Model1

final_fit %>%
  collect_predictions() %>% 
  roc_curve(class, .pred_PS) %>% 
  autoplot()
```

<img src="figs/last-fit-1.svg" width="672" />

The performance metrics from the test set indicate that we did not overfit during our tuning procedure.

The `final_fit` object contains a finalized, fitted workflow that you can use for predicting on new data or further understanding the results. You may want to extract this object, using [one of the `extract_` helper functions](https://tune.tidymodels.org/reference/extract-tune.html).


```r
final_tree <- extract_workflow(final_fit)
final_tree
#> ══ Workflow [trained] ════════════════════════════════════════════════
#> Preprocessor: Formula
#> Model: decision_tree()
#> 
#> ── Preprocessor ──────────────────────────────────────────────────────
#> class ~ .
#> 
#> ── Model ─────────────────────────────────────────────────────────────
#> n= 1514 
#> 
#> node), split, n, loss, yval, (yprob)
#>       * denotes terminal node
#> 
#>  1) root 1514 539 PS (0.64398943 0.35601057)  
#>    2) total_inten_ch_2< 41732.5 642  33 PS (0.94859813 0.05140187)  
#>      4) shape_p_2_a_ch_1>=1.251801 631  27 PS (0.95721078 0.04278922) *
#>      5) shape_p_2_a_ch_1< 1.251801 11   5 WS (0.45454545 0.54545455) *
#>    3) total_inten_ch_2>=41732.5 872 366 WS (0.41972477 0.58027523)  
#>      6) fiber_width_ch_1< 11.37318 406 160 PS (0.60591133 0.39408867)  
#>       12) avg_inten_ch_1< 145.4883 293  85 PS (0.70989761 0.29010239) *
#>       13) avg_inten_ch_1>=145.4883 113  38 WS (0.33628319 0.66371681)  
#>         26) total_inten_ch_3>=57919.5 33  10 PS (0.69696970 0.30303030) *
#>         27) total_inten_ch_3< 57919.5 80  15 WS (0.18750000 0.81250000) *
#>      7) fiber_width_ch_1>=11.37318 466 120 WS (0.25751073 0.74248927)  
#>       14) eq_ellipse_oblate_vol_ch_1>=1673.942 30   8 PS (0.73333333 0.26666667)  
#>         28) var_inten_ch_3>=41.10858 20   2 PS (0.90000000 0.10000000) *
#>         29) var_inten_ch_3< 41.10858 10   4 WS (0.40000000 0.60000000) *
#>       15) eq_ellipse_oblate_vol_ch_1< 1673.942 436  98 WS (0.22477064 0.77522936) *
```

We can create a visualization of the decision tree using another helper function to extract the underlying engine-specific fit.


```r
final_tree %>%
  extract_fit_engine() %>%
  rpart.plot(roundint = FALSE)
```

<img src="figs/rpart-plot-1.svg" width="768" />

Perhaps we would also like to understand what variables are important in this final model. We can use the [vip](https://koalaverse.github.io/vip/) package to estimate variable importance [based on the model's structure](https://koalaverse.github.io/vip/reference/vi_model.html#details). 


```r
library(vip)

final_tree %>% 
  extract_fit_parsnip() %>% 
  vip()
```

<img src="figs/vip-1.svg" width="576" />

These are the automated image analysis measurements that are the most important in driving segmentation quality predictions.


We leave it to the reader to explore whether you can tune a different decision tree hyperparameter. You can explore the [reference docs](/find/parsnip/#models), or use the `args()` function to see which parsnip object arguments are available:


```r
args(decision_tree)
#> function (mode = "unknown", engine = "rpart", cost_complexity = NULL, 
#>     tree_depth = NULL, min_n = NULL) 
#> NULL
```

You could tune the other hyperparameter we didn't use here, `min_n`, which sets the minimum `n` to split at any node. This is another early stopping method for decision trees that can help prevent overfitting. Use this [searchable table](/find/parsnip/#model-args) to find the original argument for `min_n` in the rpart package ([hint](https://stat.ethz.ch/R-manual/R-devel/library/rpart/html/rpart.control.html)). See whether you can tune a different combination of hyperparameters and/or values to improve a tree's ability to predict cell segmentation quality.



## Session information


```
#> ─ Session info  🐑  👩‍🚒  🥝   ───────────────────────────────────────
#>  hash: ewe, woman firefighter, kiwi fruit
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
#>  date     2021-12-21
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
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.1.0)
#>  rpart      * 4.1-15  2019-04-12 [1] CRAN (R 4.1.1)
#>  rpart.plot * 3.1.0   2021-07-24 [1] CRAN (R 4.1.0)
#>  rsample    * 0.1.1   2021-11-08 [1] CRAN (R 4.1.0)
#>  tibble     * 3.1.6   2021-11-07 [1] CRAN (R 4.1.0)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.1.0)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.1.0)
#>  vip        * 0.3.2   2020-12-17 [1] CRAN (R 4.1.0)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.1.0)
#>  yardstick  * 0.0.9   2021-11-22 [1] CRAN (R 4.1.0)
#> 
#>  [1] /Library/Frameworks/R.framework/Versions/4.1/Resources/library
#> 
#> ────────────────────────────────────────────────────────────────────
```
