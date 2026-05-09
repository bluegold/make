# Go Task Runner Implementation

このディレクトリには、Go によるタスクランナーの実装がレベル別に格納されています。各レベルは独立した実行環境として設計されており、段階的な機能拡張の過程を確認できます。

## ディレクトリ構成

- `builder`: 全レベルを一括でビルドするビルドスクリプト。
- `runner`: レベル番号を引数に受け取り、対応するコンパイル済みバイナリを実行する共通エントリーポイント。
- `level1/`: 基本的なビルド機能
- `level2/`: 変数展開機能
- `level3/`: 高度な制御機能（自動変数・タイムスタンプ・並行実行）
- `dist/`: `builder` によるビルド出力（`.gitignore` 対象）

---

## クラス設計と呼び出し構造

全レベルを通して、中心となるのは `TaskRunner` 構造体です。

### 主要構造体

- **`Task`**: ターゲット名、依存リスト、実行コマンドリストを保持するデータ構造。
- **`TaskRunner`**: 解析、依存解決、実行の全プロセスを管理するメイン構造体。

### 実行フローの変遷

機能の拡張に伴い、実行フェーズの設計が以下のように進化しています。

#### Level 1 & 2: 線形実行モデル

依存関係をすべて事前に解決してから、順番に実行するシンプルなモデルです。

1. **`parseFile(filepath)`**: ファイルの読み込み。
2. **`resolveDependencies(target)`**: DFS を行い、実行すべき全タスクのリスト（トポロジカル順）を作成。
3. **`execute(order)`**: リストの先頭から順にコマンドを実行。

#### Level 3: 並行実行モデル

タイムスタンプ確認や並行実行を実現するため、依存タスクをオンデマンドでトリガーするモデルへ移行しました。

1. **`parseFile(filepath)`**: ファイルの読み込み。
2. **`finalizeParsing()`**: ターゲット名などの変数を確定。
3. **`executeTask(targetName)`**:
   - そのタスクの依存タスクを並行に呼び出す（`sync.WaitGroup` + `goroutine`）。
   - 依存の完了を待ち（`wg.Wait()`）、自身のタイムスタンプを確認して実行。
   - この並行構造により、依存グラフに基づいた自然な並行実行が可能になっています。

---

## Level 1: 基本的な依存解決の設計

### トポロジカルソートと DFS

依存関係の解決には、深さ優先探索（DFS）を用いたトポロジカルソートを採用しています。
`resolveDependencies(target)` メソッドが、ターゲットから依存タスクへと再帰的に探索を行い、帰りがけ順でタスクをリストに追加することで、依存される側が先に実行される順序を保証します。

### 循環参照の検知

探索中のスタック（`stack`）を `map[string]bool` で保持し、既に探索中のタスクに再び到達した場合は循環参照（Circular Dependency）としてエラーを発生させます。

---

## Level 2: 遅延評価型変数展開の設計

### 変数エンジンと再帰展開

`expandVariables` メソッドに正規表現ベースの置換ロジックを実装しています。
変数の値そのものに変数が含まれている場合、さらに再帰的に自分自身を呼び出すことで、複雑な入れ子構造を解決します。`expanding` 配列を渡すことで、変数の循環参照を検知します。

### 遅延評価（Late Binding）

変数の展開は、パース時ではなく、`execute` メソッド内で「実行コマンドを組み立てる直前」に行われます。
これにより、定義の順序に依存せず、実行時の最新コンテキストを反映できます。

### パーサーの柔軟性

コマンド行の判定にタブ文字 `\t` だけでなくスペース `' '` も許容しており、様々な Taskfile フォーマットに対応しています。

### 環境変数の優先順位

Makefile 変数と環境変数が定義されている場合、環境変数が優先されます。

- **Level 2**: `os.Getenv(varName) > vars[varName]`
- **Level 3**: 自動変数（`$@`, `$<`, `$^`）の優先順位は `extraVars > vars > os.Getenv`

---

## Level 3: 高度な制御と並行実行の設計

### 自動変数の動的注入

`executeTask` の実行中に、そのターゲットに特有の値を `extraVars`（`map[string]string`）として生成し、展開エンジンに渡します。

- `$@`: ターゲット名
- `$<`: `task.dependencies[0]`
- `$^`: `strings.Join(task.dependencies, " ")`

### タイムスタンプ・チェックによる最適化

`needsUpdate(target, dependencies)` メソッドが、`os.Stat` を使用して日時の比較を行います。
`!os.Stat(target).IsExist()` または `depStat.ModTime().After(targetStat.ModTime())` の場合に `true` を返します。

### sync.WaitGroup による並行実行

Level 3 では、コマンド実行に `sync.WaitGroup` と `goroutine` を使用し、イベントループをブロックしない並列実行設計を採用しています。

1. **依存レベルの並行性**: 同じレベルの依存タスクは `sync.WaitGroup` で並行起動されます。
2. **タスク内の直列性**: 同一タスク内のコマンドは `for` ループ内で直列に実行されます。
3. **依存の完了を待つ**: `wg.Wait()` で全依存の完了を待ってから、自身のタイムスタンプを確認して実行します。
4. **goroutine による軽量並列実行**: 依存関係のないタスクは自然に並行実行されます。

### チャネルによる二重実行防止

既に実行中のタスクに対して再帰呼び出しが行われた場合、同じターゲットが並行に多重実行されるリスクがあります。
これを防ぐため、`map[string]chan TaskResult` を使用して、既に存在するチャネルを再利用します。

---

## ビルドと実行

### ビルド

`builder` スクリプトを実行すると、各レベルの `main.go` をコンパイルし、`dist/` ディレクトリにバイナリが生成されます。

```bash
./golang/builder
```

### 実行

`runner` スクリプトは第 1 引数にレベル番号を指定します。

```bash
./golang/runner level1 samples/01_basic/simple_build.txt
./golang/runner level2 samples/02_variables/01_basic_vars.txt
./golang/runner level3 samples/03_advanced/03_parallel.txt
```

### 統合テスト (Integration Tests)

ルートディレクトリのツールを使用して、実際のサンプルファイルを用いたテストを行います。`evaluate.rb` は自動的に `builder` を実行してからテストを開始します。

```bash
./tools/evaluate.rb golang level1
./tools/evaluate.rb golang level2
./tools/evaluate.rb golang level3
```
