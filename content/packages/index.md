---
title: Tidymodels 패키지들
---

## 설치 및 사용

* `install.packages("tidymodels")` 을 실행하여 tidymodels 생태계의 다양한 패키지들을 설치하세요.

* `library(tidymodels)` 을 실행하여 현재 R 세션에 핵심 패키지들을 로드하고 접근하세요.

<div class="package-section">

<div class="package-section-info">

## 핵심 패키지

  <p>tidymodels 핵심 패키지들은 다양한 모델링을 할 수 있도록 해 줍니다:</p>
</div>

<div class="packages">
  <div class="package">
    <img class="package-image" src="/images/tidymodels.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://tidymodels.tidymodels.org/"> tidymodels </a></h3>
      <p>tidymodels 는 아래 열거된, 모델링, 기계학습 패키지들을 설치하고 불러오는 메타패키지입니다.
      <a href="https://tidymodels.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>
  <div class="package">
    <img class="package-image" src="/images/rsample.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://rsample.tidymodels.org/">rsample</a></h3>
      <p>rsample 은 효율적인 데이터 splitting 과 resampling infrastructure 를 제공합니다. <a href="https://rsample.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>
  <div class="package">
    <img class="package-image" src="/images/parsnip.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://parsnip.tidymodels.org/"> parsnip </a></h3>
      <p>parsnip 은 내부 패키지의 문법적 디테일의 수렁에 빠지지 않고 다양한 모델을 시도하는데 사용할 수 있는 타이디하고 통합된 모델 인터페이스입니다. <a href="https://parsnip.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>  
  <div class="package">
    <img class="package-image" src="/images/recipes.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://recipes.tidymodels.org/"> recipes </a></h3>
      <p>recipes 는 피쳐엔지니어링 데이터 전처리를 위한 타이디한 인터페이스입니다. <a href="https://recipes.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>
  <div class="package">
    <img class="package-image" src="/images/workflows.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://workflows.tidymodels.org/"> workflows </a></h3>
      <p>workflows 는 전처리, 모델링, 후처리를 하나로 모읍니다. <a href="https://workflows.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div> 
  <div class="package">
    <img class="package-image" src="/images/tune.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://tune.tidymodels.org/"> tune </a></h3>
      <p>tune 은 모델의 하이퍼파라미터와 전처리 과정들을 최적화할 수 있게 해줍니다. <a href="https://tune.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>  
  <div class="package">
    <img class="package-image" src="/images/yardstick.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://yardstick.tidymodels.org/"> yardstick </a></h3>
      <p>yardstick 은 성능지표를 사용하여 모델의 효율성을 측정합니다. <a href="https://yardstick.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>
  <div class="package">
    <img class="package-image" src="/images/broom.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://broom.tidymodels.org/"> broom </a></h3>
      <p>broom 은 공통 통계 R 객체에 들어있는 정보를 사용자친화적인, 예측할 수 있는 형태로 변환합니다. 
      <a href="https://broom.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>
  <div class="package">
    <img class="package-image" src="/images/dials.png" alt=""></img>
    <div class="package-info">
      <h3><a href="https://dials.tidymodels.org/"> dials </a></h3>
      <p>dials 는 튜닝 파라미터와 파라미터 그리드를 생성하고 관리합니다.
      <a href="https://dials.tidymodels.org/" aria-hidden="true">패키지로 이동 ...</a></p>
    </div>
  </div>  

</div>
</div>

tidymodels 메타패키지 자체에 대해 알고 싶으면 다음을 방문하세요 <https://tidymodels.tidymodels.org/>.

## 특수 패키지

tidymodel 프레임워크 안에는 이 밖에도 특정한 데이터 분석과 모델링 업무를 위해 설계된 패키지들이 많이 있습니다. 이 패키지들은 `library(tidymodels)` 를 실행할 때 자동으로 불러와 지지 않기 때문에, 각각의 `library()` 호출을 통해 불러와야합니다. 이러한 패키지들은 다음과 같습니다: 

### [통계 분석 수행](/learn/statistics/)

* [infer](https://infer.netlify.com/) 에는 tidyverse-친화적인 통계 추론을 위한 high-level API 들이 있습니다.

* [corrr](https://corrr.tidymodels.org/) 패키지에는 상관행렬(correlation matrix) 작업을 위한 타이디한 인터페이스들이 있습니다.

### [로버스트한 모델 생성](/learn/models/)

* [spatialsample](http://spatialsample.tidymodels.org/) 패키지에는 resample 과 같이 resampling 함수와 클래스들이 있지만, 공간데이터에 특화되어있습니다.

* parsnip 에는 모델 정의를 포함하는 추가 패키지들이 있습니다. [discrim](https://discrim.tidymodels.org/) 에는 discriminant analysis models 들이 정의되어 있고, [poissonreg](https://poissonreg.tidymodels.org/) 에는 포아송회귀모델들이 정의되어 있습니다, [plsmod](https://plsmod.tidymodels.org/) 는 선형 프로젝션 모델들을 할 수 있게 하고, [rules](https://rules.tidymodels.org/) 은 룰베이스 분류와 회귀모형에 대해 같은 것을 합니다. [baguette](https://baguette.tidymodels.org/) 는 배깅을 통한 모델앙상블을 생성합니다.

* 레시피생성을 위한 애드온 패키지들이 있습니다. [embed](https://embed.tidymodels.org/) 에는 설명변수의 임베딩이나 프로젝션을 생성하는 스텝들이 있습니다. [textrecipes](https://textrecipes.tidymodels.org/) 에는 텍스트 처리를 위한 추가 스텝들이 있고, [themis](https://themis.tidymodels.org/) 에는 샘플링 메소드들을 이용하여 클래스 불균형문제를 개선시키는 방법들이 있습니다. 

* [tidypredict](https://tidypredict.tidymodels.org/) 와 [modeldb](https://modeldb.tidymodels.org/) 을 사용하면 예측공식을 다른 언어 (예: SQL) 로 변환시키고 데이터베이스안에서 모델을 적합시킬 수 있습니다. 

### [모델튜닝, 비교, 작업하기](/learn/work/)

* 많은 모델들의 예측값을 합치기 위해, [stacks](https://stacks.tidymodels.org/) 패키지에는 스택된 앙상블 모델링을 위한 도구들이 있습니다.

* [usemodels](https://usemodels.tidymodels.org/) 패키지를 사용하면 템플릿을 생성하고 자동으로 모델을 적합하고 튜닝하는 코드를 생성할 수 있습니다.

* [probably](https://probably.tidymodels.org/) 에는 후처리 클래스 확률추정값을 위한 도구들이 있습니다.

* [tidyposterior](https://tidyposterior.tidymodels.org/) 패키지는 이용자들이 resampling 과 베이지언 방법을 사용하여 모델들 사이에 공식 통계적 비교를 할 수 있게 해 줍니다.

* 어떤 R 객체들은 디스크에 저장하기 너무 커서 불편해집니다. [butcher](https://butcher.tidymodels.org/) 패키지는 덜 중요한 구성요소들을 제거해서 이러한 객체들의 크기를 줄일 수 있습니다.

* 예측하고 있는 데이터가 트레이닝셋으로 부터의 _외삽(extrapolations)_ 인지를 알기 위해, [applicable](https://applicable.tidymodels.org/)은 외삽을 측정하는 지표들을 제공합니다. 

### [커스템 모델링 도구 개발하기](/learn/develop/)

* [hardhat](https://hardhat.tidymodels.org/) 는 초보자가 양질의 모델링패키지를 생성할 수 있게 해 주는 _개발자용_ 패키지입니다. 
