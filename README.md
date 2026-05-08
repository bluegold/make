# Task Runner Challenge

Makefile のサブセットを解析・実行する独自のタスクランナーを構築するプロジェクトです。

## ディレクトリ構成

```text
.
├── AGENT.md            # プロジェクトの要件定義書
├── samples/            # テスト用の Taskfile サンプル
│   ├── 01_basic/       # Level 1 用サンプル
│   ├── 02_variables/   # Level 2 用サンプル
│   └── 03_advanced/    # Level 3 用サンプル
├── python/             # Python による実装
│   ├── README.md       # Python 実装の詳細ドキュメント
│   ├── level1/         # 基本機能の実装
│   ├── level2/         # 変数展開の実装
│   └── level3/         # 自動変数・タイムスタンプ・並行実行の実装
└── tools/              # 共通ユーティリティツール
    ├── evaluate.rb     # 自動評価スクリプト
    ├── clean_all.rb    # 一括クリーンアップスクリプト
    └── tests.yaml      # (将来用) テストメタデータ
```

## ツールの使い方

### 実装の評価 (evaluate.rb)

各レベルの実装が期待通りに動作するかをテストします。`.expected` ファイルとの出力比較や、並行実行のパフォーマンス計測（Level 3）も行います。

```bash
# 実行例
./tools/evaluate.rb python level1
./tools/evaluate.rb python level2
./tools/evaluate.rb python level3
```

### 成果物のクリーンアップ (clean_all.rb)

`samples/` ディレクトリ内に生成されたオブジェクトファイルやバイナリ、一時ファイルを一括で削除します。

```bash
./tools/clean_all.rb
```

## 開発ガイドライン

新しい言語で実装を追加する場合は、`AGENT.md` の仕様に従い、`tools/evaluate.rb` にその言語の実行ロジックを追加してください。
各テストケースの期待値は、`samples/` 内の各ディレクトリにある `.expected` ファイルで管理されています。
