# Ruby Level 4 Note

## 1. 目的

Level 4 では、明示的に記述されたターゲットと依存関係を実行するだけでなく、未定義ターゲットに対して利用可能な暗黙ルールを探索し、必要な依存関係を補完する。

この段階の主目的は、手書きの Makefile に近い実用性を持たせることである。

## 2. 全体構成

```text
Parser
  -> Normalizer
  -> RuleResolver / ImplicitRuleEngine
  -> Resolver
  -> Scheduler
  -> worker
```

### 各層の責務

- `Parser`
  - 明示ルール、Pattern Rule、`.PHONY` を読み取る
  - ただし、ルール選択は行わない

- `Normalizer`
  - 変数展開を行う
  - target 名と prerequisite を正規化する
  - ただし、暗黙ルールの探索は行わない

- `RuleResolver` / `ImplicitRuleEngine`
  - 明示ルールの有無を確認する
  - Pattern Rule の適用可否を判定する
  - 必要な prerequisite を生成する
  - ルール連鎖を再帰的に解決する
  - `.PHONY` を考慮する

- `Resolver`
  - 確定した DAG を topological order に並べる

- `Scheduler`
  - topological order を前提に、実行可能なタスクを worker に割り当てる

## 3. ルール探索の基本方針

Level 4 では、target が明示ルールで定義されていない場合に、Pattern Rule を用いて作成方法を探索する。

### 例

```make
%.o: %.c

app: main.o util.o
```

この場合、`main.o` および `util.o` は明示ルールを持たないが、`%.o: %.c` により次の依存が補完される。

- `main.o -> main.c`
- `util.o -> util.c`

結果として、内部的には次の DAG が形成される。

```text
main.c -> main.o -> app
util.c -> util.o -> app
```

## 4. Pattern Rule の優先順位

Pattern Rule を導入する場合、探索順を固定しなければ挙動が不安定になる。

### 優先順位

1. 明示ルール
2. Pattern Rule
3. より具体的な Pattern Rule
4. 連鎖的に解決可能なルール

### 具体性の考え方

たとえば次のルールがある場合を考える。

```make
%.o: %.c
src/%.o: src/%.c
```

`src/main.o` に対しては、`src/%.o` の方が具体的であるため、優先して適用する。

具体性の評価は、固定文字列の長さやワイルドカードの少なさを基準とする。

## 5. `.PHONY` の扱い

`.PHONY` はファイル実在性およびタイムスタンプ判定から切り離して扱う。

### 要件

- `.PHONY` に含まれる target は毎回実行対象とする
- ファイルが存在していてもスキップしない
- `clean` のような命令専用 target を表現できるようにする

## 6. ルール連鎖

暗黙ルールは 1 回適用して終了するのではなく、必要に応じて連鎖的にたどる必要がある。

### 例

```make
%.c: %.src
%.o: %.c
```

`app.o` を構築する場合、以下の順で解決する。

1. `app.o` に対して `%.o: %.c` を適用する
2. prerequisite として `app.c` を得る
3. `app.c` に対して `%.c: %.src` を適用する
4. prerequisite として `app.src` を得る

このように、`RuleResolver` は再帰的に rule を解決する必要がある。

## 7. データモデル

Level 4 では、以下のような値オブジェクトを追加すると整理しやすい。

```ruby
Rule = Data.define(:target_pattern, :prerequisite_patterns, :commands, :phony)
RuleMatch = Data.define(:rule, :stem, :specificity)
ResolvedTask = Data.define(:name, :dependencies, :commands, :phony, :origin_rule)
```

### 役割

- `Rule`
  - パース済みのルール定義
- `RuleMatch`
  - target に適用する候補 rule と stem を保持する
- `ResolvedTask`
  - 実行可能な形に正規化されたタスク

## 8. 実装順序

Level 4 の実装は、以下の順序が妥当である。

1. `Parser` に Pattern Rule と `.PHONY` を読ませる
2. `RuleResolver` を実装し、単一の Pattern Rule を適用する
3. 明示ルール優先を導入する
4. ルール連鎖を導入する
5. 具体性順の優先を導入する
6. `Resolver` と `Scheduler` に接続する

## 9. 期待される効果

Level 4 を導入することで、以下のような用途に対応しやすくなる。

- `%.o: %.c` を用いた単純なビルド
- `.PHONY` を用いた cleanup 処理
- 明示ルールと暗黙ルールの併用
- 連鎖的な暗黙ルールによる段階的ビルド

## 10. 位置づけ

本ノートは Level 4 の設計メモであり、全体設計書の代替ではない。

- `README.md`: 全体概要
- `DESIGN.md`: 共通設計
- `notes/resolver.md`: DFS / Resolver の補足
- `notes/level3.md`: Level 3 の実行モデル補足
- `notes/level4.md`: Level 4 の暗黙ルール設計補足
