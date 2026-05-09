# TypeScript Task Runner Implementation

このディレクトリには、TypeScript によるタスクランナーの実装がレベル別に格納されています。各レベルは独立した実行環境として設計されており、段階的な機能拡張の過程を確認できます。

## ディレクトリ構成

- `builder`: 全レベルを一括でコンパイルするビルドスクリプト。
- `runner`: レベル番号を引数に受け取り、対応するコンパイル済み JS を実行する共通エントリポイント。
- `level1/`: 基本的なビルド機能
- `level2/`: 変数展開機能
- `level3/`: 高度な制御機能（自動変数・タイムスタンプ・並行実行）
- `dist/`: `builder` によるコンパイル出力（`.gitignore` 対象）

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

1. **`parseFile(filepath)`**: ファイルの読み込み。
2. **`resolveDependencies(target)`**: DFS を行い、実行すべき全タスクのリスト（トポロジカル順）を作成。
3. **`execute(order)`**: リストの先頭から順にコマンドを実行。

#### Level 3: 再帰・並行実行モデル

タイムスタンプ確認や並行実行を実現するため、オンデマンドで依存タスクをトリガーするモデルへ移行しました。

1. **`parseFile(filepath)`**: ファイルの読み込み。
2. **`finalizeParsing()`**: ターゲット名などの変数を確定。
3. **`executeTask(targetName)`**:
   - そのタスクの依存タスクを再帰的に呼び出す。
   - `Promise.all` で依存の完了を待ち、自身のタイムスタンプを確認して実行。
   - この再帰構造により、依存グラフに基づいた自然な並行実行が可能になっています。

---

## Level 1: 基本的な依存解決の設計

### トポロジカルソートと DFS

依存関係の解決には、深さ優先探索（DFS）を用いたトポロジカルソートを採用しています。

`resolveDependencies(target)` メソッドが、ターゲットから依存タスクへと再帰的に探索を行い、帰りがけ順でタスクをリストに追加することで、依存される側が先に実行される順序を保証します。

### 循環参照の検知

探索中のスタック（`stack`）を `Set` で保持し、既に探索中のタスクに再び到達した場合は循環参照（Circular Dependency）としてエラーを発生させます。

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

- **Level 2**: `process.env[varName] || this.variables.get(varName)`
- **Level 3**: 自動変数（`$@`, `$<`, `$^`）の優先順位は `extraVars > this.variables > process.env`

---

## Level 3: 高度な制御と並行実行の設計

### 自動変数の動的注入

`executeTask` の実行中に、そのターゲットに特有の値を `extraVars`（`Map<string, string>`）として生成し、展開エンジンに渡します。

- `$@`: ターゲット名
- `$<`: `task.dependencies[0]`
- `$^`: `task.dependencies.join(' ')`

### タイムスタンプ・チェックによる最適化

`needsUpdate(target, dependencies)` メソッドが、`fs.statSync` を使用して日時の比較を行います。
`!fs.existsSync(target)` または `depStat.mtime > targetStat.mtime` の場合に `true` を返します。

### spawnSync ベースの同期実行

Level 1-2 では、コマンド実行に `spawnSync('sh', ['-c', cmd], { stdio: 'pipe' })` を使用しています。
これにより、バッククォートによる出力のキャプチャが可能になり、"Executing:" ログの出力順序を確実に制御できます。

### spawn ベースの非同期スケジューラ

Level 3 では、コマンド実行に `child_process.spawn` を使用し、イベントループをブロックしない非同期設計を採用しています。

1. タスクが呼び出されると、`Promise.all` で依存タスクの `executeTask` を並行起動します。
2. 各タスク内では `spawn('sh', ['-c', cmd], { stdio: 'inherit' })` でコマンドを実行し、`Promise` で完了を待機します。
3. 依存関係のないタスクは Node.js のイベントループ上で自然に並行実行されます。

---

## ビルドと実行

### ビルド

`builder` スクリプトを実行すると、`tsc` により `dist/` ディレクトリにコンパイル済み JavaScript が生成されます。

```bash
./typescript/builder
```

### 実行

`runner` スクリプトは第 1 引数にレベル番号を指定します。

```bash
./typescript/runner level1 samples/01_basic/simple_build.txt
./typescript/runner level2 samples/02_variables/01_basic_vars.txt
./typescript/runner level3 samples/03_advanced/03_parallel.txt
```

### 統合テスト (Integration Tests)

ルートディレクトリのツールを使用して、実際のサンプルファイルを用いたテストを行います。`evaluate.rb` は自動的に `builder` を実行してからテストを開始します。

```bash
./tools/evaluate.rb typescript level1
./tools/evaluate.rb typescript level2
./tools/evaluate.rb typescript level3
```
