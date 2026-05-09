# Ruby Resolver Note

このノートは、`Resolver` の DFS 依存解決をまとめたものです。

## 1. まず前提

この課題の依存関係は、単純な木ではなく **DAG**
（有向非循環グラフ）として考えるのが正確です。

理由は、同じリソースが複数のターゲットから参照されるからです。

```text
        all
         |
      deploy
      /    \
   build   test
      \    /
       init
```

このように `init` のようなノードは、複数の親から共有されます。
木だと「1 回しか親を持てない」ので、表現として足りません。

## 2. Resolver の役割

`Resolver` は「何を、どの順で実行するか」を決めるだけです。

ここでやること:

- target から依存をたどる
- 依存を先に、親を後に並べる
- 同じノードを 2 回積まない
- 循環があれば止める

ここでやらないこと:

- コマンドの実行
- 変数の展開
- タイムスタンプの判定

## 3. 状態の持ち方

Resolver は 3 つの状態を持つ。

- `visited`
  - もう処理済みのノード
  - 2 回目に来ても積まない

- `visiting`
  - 今まさに探索中のノード
  - ここに戻ったら循環依存

- `order`
  - 最終的な実行順の配列
  - 依存が先、親が後

Ruby では `Set` が自然に使える。

## 4. 実際の DFS の流れ

今の実装は、`visit(target)` が次のように動く。

1. すでに `visited` なら何もしない
2. `visiting` にあれば循環依存として失敗する
3. `visiting` に入れる
4. 依存を順に再帰探索する
5. 探索が終わったら `visiting` から外す
6. `visited` に入れる
7. `order` に積む

コードの対応は [ruby/level1/lib/task_runner/resolver.rb](/home/kaneko/work/tmp/make/ruby/level1/lib/task_runner/resolver.rb)。

## 5. 共有ノードと重複排除

同じノードが複数の親から参照される場合でも、`Resolver` はそのノードを 1 回だけ `order` に積む。

たとえば次のような構造を考える。

```text
all -> deploy
deploy -> build, test
build -> init
test -> init
```

`init` は `build` 側の探索で一度たどられ、その時点で `order` に積まれる。
その後 `test` 側から再び `init` に到達しても、すでに `visited` 済みなので追加しない。

挙動を整理すると次の通り。

- 初回到達時だけ `order` に入る
- 再訪時は `visited` によりスキップされる
- まだ探索中のノードに戻った場合は `visiting` により循環依存としてエラーになる

この重複排除により、共有ノードを持つ DAG でも安定して 1 本の実行順リストを作れる。

たとえば次の DAG では、`build` と `test` は `init` の完了後に同時に `ready` になる。

```text
all -> deploy
deploy -> build, test
build -> init
test -> init
```

このときの流れはこうなる。

1. `init` が終わる
2. `build` と `test` の `indegree` がどちらも 0 になる
3. `ready` に `build` と `test` が並ぶ
4. 空いている worker があれば、両方を並列に実行できる

したがって、並列実行は「同じ親を持つ兄弟タスクが、依存解決の結果として同時に ready になる」ことで発生する。

## 6. どのノードが `order` に入るか

`Resolver` は **Task として定義されているものだけ** を `order` に入れる。

たとえば `main.c` のような実ファイルは、タスクとして定義されていなければ `order` に入らない。
それはあくまでコマンド実行時や更新判定時に参照するファイルである。

## 7. `Resolver` の結果は「実行順リスト」

`Resolver` の返す配列は、単なる依存の列挙ではない。
あくまで「この順で実行すれば依存関係が満たされる」という順序付きリストである。

イメージ:

```text
DFS 探索
  -> 依存を先に全部たどる
  -> 帰りがけに自分を積む
  -> 結果として topological order になる
```

上の DAG 例で `all` を解決すると、`dependencies.each` の順序に従って、最終的な `topological order` は次のようになる。

```text
init, build, test, deploy, all
```

流れはこうなる。

1. `all` から `deploy` に入る
2. `deploy` から `build` に入る
3. `build` から `init` に入る
4. `init` は依存を持たないので先に `order` に入る
5. `build` を `order` に入れる
6. `deploy` の次の依存 `test` に入る
7. `test` から `init` に入るが、`init` はすでに `visited` 済みなので追加しない
8. `test` を `order` に入れる
9. `deploy` を `order` に入れる
10. 最後に `all` を `order` に入れる

## 8. このノートの位置づけ

これは resolver と DFS の補助メモであり、level3 の実行モデルは含めない。

- `README.md`: 全体の概要
- `DESIGN.md`: 共通設計
- `notes/resolver.md`: resolver / DFS の補足
- `notes/level3.md`: level3 の実行モデルの補足
