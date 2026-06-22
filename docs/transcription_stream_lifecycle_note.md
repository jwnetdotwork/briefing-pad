# 文字起こしがパート切替後に表示されなくなった原因と対策

## 概要

一度停止してパートを切り替えたあと、再度「開始」しても音声認識は動いているのに文字起こしが画面に出ない問題があった。

調査の結果、原因は **音声認識の `AsyncStream` をサービス寿命で1回だけ共有していたこと** と、**`SessionViewModel` 側の consumer loop が最初の録音セッションで終了した後に再接続されていなかったこと** だった。

## 事実として分かったこと

- `SpeechTranscriptionService` 側では認識結果が継続して出力されていた。
- しかし、2回目以降の録音開始では `SessionViewModel.handleTranscriptSegment` が発火していなかった。
- `SessionViewModel.startTranscription` 内の `for await segment in transcriptionService.results` は、最初のセッション後に終了していた。
- その後、同じ `results` を使い回していたため、新しい録音セッションの segment を受け取る consumer がいなくなっていた。

## 原因

### 直接原因

`SpeechTranscriptionService` が `AsyncStream` を `init` で1回だけ作成し、その stream を複数回の録音開始で使い回していた。

### 構造的な原因

- `results` の寿命が「録音1回分」ではなく「サービス全体」に固定されていた。
- `SessionViewModel` は録音開始ごとに新しい consumer を作る前提ではなかった。
- パート切替や停止処理で consumer が終了すると、次の録音時に再購読されない状態になっていた。

## 対策

- `SpeechTranscriptionService` は `startTranscription` ごとに新しい `AsyncStream` を生成する。
- `SessionViewModel` は毎回その run 専用の stream を受け取り、購読し直す。
- `yield` の結果と consumer loop の開始・終了をログ化し、どこで経路が切れたか追えるようにする。
- 再現テストを追加し、パート切替後の継続性を保証する。

## 実装後の確認ポイント

- 1回目の録音で `handleTranscriptSegment` が発火すること。
- 停止後にパートを切り替えても、2回目の録音で `handleTranscriptSegment` が発火すること。
- `SpeechTranscriptionService` 側で結果が出ているのに `SessionViewModel` 側が受けていない状態にならないこと。

## 再発防止

- `AsyncStream` を「サービス全体で共有する通信路」として扱わない。
- 音声認識のような session-based な処理は、`start` と `stop` の単位で stream と consumer を必ず作り直す。
- 停止後再開、パート切替、録音中断の各ケースを再現テストで押さえる。

