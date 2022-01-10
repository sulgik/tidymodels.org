---
title: "모델 파라미터 튜닝하기"
weight: 4
tags: [rsample, parsnip, tune, dials, workflows, yardstick]
categories: [tuning]
description: | 
  모델 훈련동안 직접 학습될 수 없는 하이퍼파라미터의 가장 좋은 값을 추정합니다.
---






## 들어가기 {#intro}

어떤 모델 파라미터는 모델 트레이닝 중 데이터셋으로부터 직접 학습이 되지 않습니다. 이러한 파라미터를 **하이퍼파라미터** 라고 부릅니다. 트리 기반 모델에서 나누어지는 곳에서 샘플되는 설명변수의 개수 (tidymodels 에서 `mtry` 로 부름) 혹은 부스티드 트리 모델에서 학습속도(`learn_rate` 로 부름) 가 하이퍼파라미터에 포함됩니다. 모델 트레이닝 중 하이퍼파라미터를 학습하는것 대신, 리샘플한 데이터셋에 여러 모형을 훈련하고 이 모델들의 성능을 탐색해서 가장 좋은 값을 _추정_ 할 수 있습니다. 이와 같은 프로세스를 **튜닝** 이라고 부릅니다.


이 장에 있는 코드를 사용하려면,  다음 패키지들을 인스톨해야 합니다: rpart, rpart.plot, tidymodels, and vip.


```r
library(tidymodels)  # for the tune package, along with the rest of tidymodels

# Helper packages
library(rpart.plot)  # for visualizing a decision tree
library(vip)         # for variable importance plots
```

{{< test-drive url="https://rstudio.cloud/project/2674862" >}}

## 세포 이미지 데이터, 계속 {#data}

이전의 [*리샘플링으로 모델 평가하기*](/start/resampling/) 장에서, 전문가들이 잘세그멘트됨(`WS`)과 잘못세그멘트됨(`PS`)으로 라벨한 세포 이미지 데이터셋을 소개했었습니다. 잘/잘못 세그멘트된 이미지인지를 예측하기 위해 [랜덤포레스트모델](/start/resampling/#modeling)을 훈련해서 생물학자가 잘못 세그멘트된 세포이미지들을 분석에서 필터링하도록 했습니다. 이 데이터셋에 우리 모델의 성능을 추정하기 위해 [리샘플링](/start/resampling/#resampling) 을 사용했었습니다.


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

과적합을 피하기 위해 모델 하이퍼파라미터를 튜닝할 것입니다. `cost_complexity` 의 값을 튜닝하면 우리 트리를  [pruning](https://bradleyboehmke.github.io/HOML/DT.html#pruning) 하여 도움이 됩니다. 더 복잡한 트리의 에러 레이트에 코스트 혹은 페널티를 추가합니다; 0 에 가까운 코스트는 프룬된 트리노드 개수를 감소시키고 과적합된 나무를 제공하기 쉽습니다. 그러나 높은 코스트는 프룬된 트리 노드의 개수를 증가시키고 상반된 문제&mdash;언더핏 트리를 산출할 수 있습니다. 반면에 `tree_depth` 를 튜닝하면 우리 트리를 어떤 뎁스에 다다른 뒤 더 자라는 것을 [방지](https://bradleyboehmke.github.io/HOML/DT.html#early-stopping) 하는 도움을 줍니다. 우리의 목적은 이러한 하이퍼파라미터들을 튜닝하여 우리모델이 이미지 세그멘테이션을 가장 잘 예측하기 위한 값들로 튜닝하는 것입니다.

튜닝 프로세스를 시작하기 전에, 하이퍼파라미터 기본값으로 모델을 훈련시켰을 때와 같이 우리 데이터를 트레이닝셋과 테스트 셋으로 분리합니다. [전](/start/resampling/)과 같이 `strata = class` 를 하여 층화 샘플링을 이용하여 트레이닝과 테스팅 셋이 세그멘테이션 종류비율이 같도록 합니다.


```r
set.seed(123)
cell_split <- initial_split(cells %>% select(-case), 
                            strata = class)
cell_train <- training(cell_split)
cell_test  <- testing(cell_split)
```

모델을 튜닝하기 위해 트레이닝 데이터를 사용합니다.

## 하이퍼파라미터 튜닝 {#tuning}

[`decision_tree()`](https://parsnip.tidymodels.org/reference/decision_tree.html) 모델을 [rpart](https://cran.r-project.org/web/packages/rpart/index.html) 엔진과 함께 사용하여 parsnip 패키지로 시작해 봅시다. decision tree 하이퍼파라미터 `cost_complexity` and `tree_depth` 를 튜닝하기 위해, 튜닝하고 싶은 하이퍼파라미터를 식별하는 모델 spec 을 생성합니다. 


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

여기서 `tune()` 를 placeholder 로 간주합니다. 튜닝 프로세스 후, 이러한 하이퍼파라미터 각각에 수치값 하나씩을 결정할 것입니다. 현재는 우리 parsnip 모델 객체를 명시하고 우리가 `tune()` 할 하이퍼파라미터를 식별합니다.

(전체 트레이닝셋같은) 하나의 데이터셋에 이 스펙을 트레이닝하고 어떤 하이퍼파라미터 값이 되어야 하는지를 학습할 수 없습니다. 대신, 우리는 리샘플된 데이터를 사용하여 모델 여러개를 훈련하고 어떤 모델이 가장 좋은 결과를 얻었는지 볼 _수 있습니다._ 레귤러 그리드 값을 생성하여 각 하이퍼파라미터에 편리한 함수들을 사용해 볼 수 있습니다:


```r
tree_grid <- grid_regular(cost_complexity(),
                          tree_depth(),
                          levels = 5)
```

[`grid_regular()`](https://dials.tidymodels.org/reference/grid_regular.html) 함수는 [dials](https://dials.tidymodels.org/) 패키지에 있습니다. 이 함수는 각 하이퍼파라미터에 시도해볼 합리적인 값들을 선택합니다; 여기서는 두 경우에 5를 시도합니다. 두 개를 튜닝하므로, `grid_regular()` 는 5 `\(\times\)` 5 = 25 개의 각기 다른 튜닝 조합을 타이디 티블 포맷으로 반환합니다.


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

여기에, 0.1 까지 변하는 `cost_complexity` 의 5 가지 값 모두를 볼 수 있습니다. 이러한 값들은 `tree_depth` 의 5 개 값 각각에 대해 반복됩니다:


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


25 개 후보 의사결정 나무 모델로 채워진 그리드로 무장하여, 튜닝을 위해 [cross-validation folds](/start/resampling/)을 생성합시다:


```r
set.seed(234)
cell_folds <- vfold_cv(cell_train)
```

Tuning in tidymodels 에서 튜닝하려면 [rsample](https://rsample.tidymodels.org/) 패키지로 생성된 리샘플된 객체가 필요합니다.

## 그리드 모델튜닝 {#tune-grid}

튜닝할 준비가 되었습니다! Let's use [`tune_grid()`](https://tune.tidymodels.org/reference/tune_grid.html) 를 사용하여 각 튜닝된 하이퍼파라미터로 선택한 모든 다른 값들에 모형을 적합합니다. 튜닝을 위한 객체를 만드는 옵션 몇 가지가 있습니다:

+ 레시피나 모델을 따라 모델 스펙을 튜닝하기

+ 모델 스펙과 레시피 혹은 모델 전처리과정을 묶는 [`workflow()`](https://workflows.tidymodels.org/)를 튜닝하기. 

여기서 우리는 `workflow()`를 직관적인 공식과 함께 사용합니다; 이 모델이 더 관여된 데이터 전처리를 필요하다면, `add_formula()` 대신 `add_recipe()` 를 사용할 수 있습니다.


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

우리 튜닝 결과를 얻었다면, 시각화를 통해 이를 탐색하고, 이후 가장 좋은 결과를 선택할 수 있습니다. `collect_metrics()` 함수는 타이티 티블을 모든 결과와 함께 제공합니다. 25 개의 후보 모델과 두개의 지표, `accuracy` 와 `roc_auc` 가 있고, 각 `.metric` 과 모델마다 하나의 행을 얻었습니다.


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

이 결과를 플롯하여 더 많은 것을 얻을 수 있습니다:


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

두 지표 기준으로 depth 가 1 인 "stubbiest" 트리가 `cost_complexity` 의 모든 후보 값들을 통틀어 가장 나쁜 모델임을 알 수 있습니다. 깊이가 15 인 가장 깊은 트리가 더 성능이 좋았습니다. 하지만, 이러한 값들 사이에 가장 좋은 트리는 depth 가 4 인 트리인 것 같습니다. [`show_best()`](https://tune.tidymodels.org/reference/show_best.html) 함수는 기본값으로 가장 좋은 5 개 후보를 보여줍니다:


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

[`select_best()`](https://tune.tidymodels.org/reference/show_best.html) 함수를 사용하여 최적의 decision tree model 의 하이퍼파라미터 값을 추출할 수도 있습니다:


```r
best_tree <- tree_res %>%
  select_best("accuracy")

best_tree
#> # A tibble: 1 × 3
#>   cost_complexity tree_depth .config              
#>             <dbl>      <int> <chr>                
#> 1    0.0000000001          4 Preprocessor1_Model06
```

이는 세포 이미지 데이터셋에서 정확도를 최대화하는 `tree_depth` 와 `cost_complexity` 값입니다.


## 최종 모델 {#final-model}

`select_best()` 의 값들로 우리 워크플로 객체 `tree_wf` 를 업데이트 (혹은 마무리)할 수 있습니다.


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

튜닝이 완료됐습니다!

### 마지막 적합

마지막으로 우리 최종모델을 트레이닝 데이터에 적합하고 테스트 데이터를 사용하여 새로운 데이터에서 예측되는 모델 성능을 추정해 봅시다. [`last_fit()`](https://tune.tidymodels.org/reference/last_fit.html) 함수를 우리의 최종완성된 모델과 사용할 수 있습니다; 이 함수는 최종완료된 모델을 전체 트레이닝 데이터셋에 _적합_하고, 테스팅 데이터에 최종완료된 모델을 _평가_합니다.


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

테스트셋에서 성능 지표들은 우리가 튜닝 과정 동안 과적합하지 않았음을 가르킵니다.

`final_fit` 객체는 새로운 데이터에서 예측하거나 결과를 더 이해하는데 사용할 수 있는 최종완료되고, 적합된 워크플로를 포함합니다. 이 객체를 추출하고 싶으면 [`extract_` 도우미함수 중 하나](https://tune.tidymodels.org/reference/extract-tune.html)를 사용하면 됩니다.


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

우리는 이 최종모델에서 어떤 변수가 중요한지 알고 싶을 것입니다. [vip](https://koalaverse.github.io/vip/) 패키지를 써서 [모델구조에 기반하여](https://koalaverse.github.io/vip/reference/vi_model.html#details) variable importance 를 추정할 수 있습니다.


```r
library(vip)

final_tree %>% 
  extract_fit_parsnip() %>% 
  vip()
```

<img src="figs/vip-1.svg" width="576" />

이 변수들은 세그멘테이션 품질 예측을 좌우하는 데 가장 중요한 자동화된 이미지 분석 측정값들입니다.


다른 의사결정 나무 하이퍼파라미터를 튜닝할 수 있는지 없는지를 탐색하는 것은 독자에게 남겨두겠습니다. [reference docs](/find/parsnip/#models) 를 탐색하거나 `args()` 함수를 사용하여 어떤 parsnip 객체 인수들이 있는지를 볼 수 있습니다:


```r
args(decision_tree)
#> function (mode = "unknown", engine = "rpart", cost_complexity = NULL, 
#>     tree_depth = NULL, min_n = NULL) 
#> NULL
```

우리가 여기서 사용하지 않은 하이퍼파라미터, `min_n` 을 튜닝할 수 있는데, 어떤 노드에서 split 하기 위해 최소 `n` 을 설정합니다. 이는 의사결정 나무들의 또 하나의 early stopping 방법인데 이는 과적합을 방지하는데 도움을 줄 수 있습니다. 이 [searchable table](/find/parsnip/#model-args)을 사용하여 rpart 패키지에 있는 `min_n` 의 원 인수를 구할 수 있습니다. ([hint](https://stat.ethz.ch/R-manual/R-devel/library/rpart/html/rpart.control.html)) 트리의 세포 세그멘테이션 품질 예측 성능을 개선하기 위해 하이퍼파라미터의 다른 조합을 튜닝할 수 있는지 시도해보세요.



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
#>  rlang      * 0.4.12  2021-10-18 [1] CRAN (R 4.0.2)
#>  rpart      * 4.1-15  2019-04-12 [1] CRAN (R 4.0.3)
#>  rpart.plot * 3.1.0   2021-07-24 [1] CRAN (R 4.0.2)
#>  rsample    * 0.1.0   2021-05-08 [1] CRAN (R 4.0.2)
#>  tibble     * 3.1.5   2021-09-30 [1] CRAN (R 4.0.2)
#>  tidymodels * 0.1.4   2021-10-01 [1] CRAN (R 4.0.2)
#>  tune       * 0.1.6   2021-07-21 [1] CRAN (R 4.0.2)
#>  vip        * 0.3.2   2020-12-17 [1] CRAN (R 4.0.2)
#>  workflows  * 0.2.4   2021-10-12 [1] CRAN (R 4.0.2)
#>  yardstick  * 0.0.8   2021-03-28 [1] CRAN (R 4.0.2)
#> 
#> [1] /Library/Frameworks/R.framework/Versions/4.0/Resources/library
```
