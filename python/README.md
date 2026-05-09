# Python Task Runner Implementation

このディレクトリには、Python によるタスクランナーの実装がレベル別に格納されています。各レベルは独立した実行環境として設計されており、段階的な機能拡張の過程を確認できます。

## ディレクトリ構成

- `level1/`: 基本的なビルド機能
- `level2/`: 変数展開機能
- `level3/`: 高度な制御機能（自動変数・タイムスタンプ・並行実行）

---

## クラス設計と呼び出し構造

全レベルを通して、中心となるのは `TaskRunner` クラスです。

### 主要クラス

- **`Task`**: ターゲット名、依存リスト、実行コマンドリストを保持するデータ構造。
- **`TaskRunner`**: 解析、依存解決、実行の全プロセスを管理するメインクラス。

### 実行フローの変遷

機能の拡張に伴い、実行フェーズの設計が以下のように進化しています。

#### Level 1 & 2: 線形実行モデル

依存関係をすべて事前に解決してから、順番に実行するシンプルなモデルです。

1. **`parse_file(filepath)`**: ファイルの読み込み。
2. **`resolve_dependencies(target)`**: DFS を行い、実行すべき全タスクのリスト（トポロジカル順）を作成。
3. **`execute(order)`**: リストの先頭から順にコマンドを実行。

#### Level 3: 再帰・並行実行モデル

タイムスタンプ確認や並行実行を実現するため、オンデマンドで依存タスクをトリガーするモデルへ移行しました。

1. **`parse_file(filepath)`**: ファイルの読み込み。
2. **`finalize_parsing()`**: ターゲット名などの変数を確定。
3. **`execute_task(target_name)`**:
   - そのタスクの依存タスクを再帰的に呼び出す。
   - 依存が完了（`Future.result()`）したら、自身のタイムスタンプを確認して実行。
   - この再帰構造により、依存グラフに基づいた自然な並行実行が可能になっています。

---

## Level 1: 基本的な依存解決の設計

### トポロジカルソートと DFS

依存関係の解決には、深さ優先探索（DFS）を用いたトポロジカルソートを採用しています。
`resolve_dependencies(target)` メソッドが、ターゲットから依存タスクへと再帰的に探索を行い、帰りがけ順でタスクをリストに追加することで、依存される側が先に実行される順序を保証します。

### 循環参照の検知

探索中のスタック（`stack`）をセットで保持し、既に探索中のタスクに再び到達した場合は循環参照（Circular Dependency）としてエラーを発生させます。

---

## Level 2: 遅延評価型変数展開の設計

### 変数エンジンと再帰展開

`expand_variables` メソッドに正規表現ベースの置換ロジックを実装しています。
変数の値そのものに変数が含まれている場合、さらに再帰的に自分自身を呼び出すことで、複雑な入れ子構造を解決します。`expanding` リストを渡すことで、変数の循環参照を検知します。

### 遅延評価（Late Binding）

変数の展開は、パース時ではなく、`execute` メソッド内で「実行コマンドを組み立てる直前」に行われます。
これにより、定義の順序に依存せず、実行時の最新コンテキストを反映できます。

---

## Level 3: 高度な制御と並行実行の設計

### 自動変数の動的注入

`execute_task` の実行中に、そのターゲットに特有の値を `extra_vars` 辞書として生成し、展開エンジンに渡します。

- `$@`: ターゲット名
- `$<`: `task.dependencies[0]`
- `$^`: `" ".join(task.dependencies)`

### タイムスタンプ・チェックによる最適化

`needs_update(target, dependencies)` メソッドが、`os.path.getmtime` を使用して日時の比較を行います。
`not os.path.exists(target)` または `dep_mtime > target_mtime` の場合に `True` を返します。

### ThreadPoolExecutor による非同期スケジューラ

Level 3 では、`execute_task` は `Future` オブジェクトを返します。

1. タスクが呼び出されると、まず依存タスクの `execute_task` を呼び出し、その `Future` リストを保持します。
2. 内部関数 `run_task` を定義し、その中で `[f.result() for f in dep_futures]` を実行して依存関係の完了を待ちます。
3. `executor.submit(run_task)` により、スレッドプール上で依存関係の解決とコマンド実行が非同期に行われます。

---

## テスト方法

### 統合テスト (Integration Tests)

ルートディレクトリのツールを使用して、実際のサンプルファイルを用いたテストを行います。

```bash
# Level 1-3 のテスト
./tools/evaluate.rb python level1
./tools/evaluate.rb python level2
./tools/evaluate.rb python level3
```

### ユニットテスト (Unit Tests)

ロジック単体の検証を行うための Python 標準の `unittest` です。

```bash
# 各レベルのユニットテスト
python3 python/level1/test/test_runner.py
python3 python/level2/test/test_runner.py
python3 python/level3/test/test_runner.py
```
