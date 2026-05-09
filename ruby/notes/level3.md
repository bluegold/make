# Ruby Level 3 Note

level3 は、変数展開そのものよりも「どう並列に捌くか」が主題になる。
そのため、level2 の延長ではあるが、実行モデルはかなり別物になる。

## 1. 全体の流れ

```text
Taskfile
  |
  v
Parser
  - 生の target / dependency / command を読む
  |
  v
Normalizer
  - target 名を展開する
  - dependency を展開して配列化する
  - 実行可能な Program に整える
  |
  v
Scheduler
  - 依存関係を数える
  - ready なタスクを並べる
  - タイムスタンプでスキップ判断する
  - worker に投げる
  |
  +--> worker Ractor 1
  +--> worker Ractor 2
  +--> worker Ractor 3
           ...
  |
  v
結果の回収
  - 成功なら依存解除
  - 失敗ならエラー終了
```

## 2. 責務分担

### Parser

- Taskfile を読み込む
- まだ意味づけはしない
- 変数展開や依存分割はしない

### Normalizer

- target 名を展開する
- dependency を展開して空白分割する
- 実行系が扱いやすい形に整える

### Scheduler

- 依存制約を保ったまま、実行可能なタスクを選ぶ
- topological order を基準に ready queue を組む
- タイムスタンプで不要な実行を飛ばす
- worker からの完了通知を受けて次のタスクを解放する

### worker Ractor

- 1 タスク分のコマンドを実行する
- `$@`, `$<`, `$^` などの自動変数を注入する
- 実行結果を返す

## 3. 自動変数の位置

自動変数は Scheduler が決めるのではなく、worker 側で作る。

- `$@` = 現在の target 名
- `$<` = 最初の dependency
- `$^` = すべての dependency

これはタスクごとに値が変わるため、依存解決とは分けて扱う。

## 4. タイムスタンプ判定の位置

`needs_update?` は Scheduler 側に置く。

理由は、これは「そのタスクをそもそも worker に投げるか」を決める制御だから。

- target が存在しなければ実行
- dependency が target より新しければ実行
- そうでなければスキップ

実行する前に判断したほうが、並列ワーカーの無駄が減る。

## 5. topological order と並列実行の関係

level3 は、Resolver が作った topological order をそのまま 1 件ずつ直列実行するわけではない。
topological order は、あくまで **依存制約を崩さないための基準順** として使う。

今の実装では、`Resolver` の結果から次の情報を作る。

- `reachable_order`
  - topological order に相当する順序付きリスト
- `indegree`
  - まだ完了していない依存の数
- `ready`
  - 依存がすべて解決済みで、今すぐ投げられるタスク

ここから先は、`ready` に入ったものだけを空いている worker に送る。
つまり並列実行は、**「複数の依存を持つ 1 タスクを同時に分散する」ことではない**。

並列になるのは、同じ時点で ready になった複数タスクがあるときである。

```text
init
  -> build
  -> test
      -> deploy
```

のように、ある層のタスク群が互いに独立なら、その層の複数タスクを別 worker に振れる。

実装の感覚としては次の通り。

1. topological order で扱う候補を決める
2. その中から `indegree == 0` のものを `ready` に入れる
3. 空いている Ractor に `ready` 先頭から渡す
4. 完了通知が来たら依存先の `indegree` を減らす
5. `indegree == 0` になったタスクを `ready` に追加する

このため、並列性は「依存グラフの同じ層に複数の ready タスクがあるか」で決まる。
1 つのターゲットに dependency が複数あること自体が直接並列化を生むわけではない。
むしろ、その dependency 群が先に並列に処理され、その完了後に親タスクが ready になる、という順序になる。
## 6. Ractor の役割

level3 では Ractor を「並列 worker」と「結果の受け渡し」に使う。

### worker 側

- 仕事を受ける
- コマンドを実行する
- 結果を返す

### Scheduler 側

- 仕事を配る
- 結果を受け取る
- 次に進めるタスクを解放する

この分離により、Scheduler はグラフ制御に集中できる。

## 7. なぜ Executor を薄くするのか

level1 / level2 では Executor が「実行そのもの」を握っていてよい。
level3 では並列制御が本体になるので、Executor は Scheduler への入口だけにしたほうが見通しがよい。

そのため level3 では:

- `Executor` = 入口
- `Scheduler` = 実働

という形にしている。

## 8. 実装上の注意

- Ractor に渡すデータはできるだけ freeze する
- `Program` は shareable に寄せる
- メッセージは単純な Hash にする
- worker の数は固定しすぎず、将来調整できる形にする

## 9. このノートの位置づけ

これは level3 実装の補助メモであり、全体設計書の代わりではない。

- `README.md`: 全体の概要
- `DESIGN.md`: 共通設計
- `notes/resolver.md`: resolver / DFS の補足
- `notes/level3.md`: level3 の実行モデルの補足
