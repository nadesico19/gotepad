# Gotepad

[简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

Gotepad は、囲碁の棋譜作成、対局検討、棋譜整理を目的としたクロスプラットフォームクライアントです。盤面と棋譜のコアロジックは C++17 で実装され、クライアントは Godot 4.7.1（非 .NET 版）と GDExtension で構築されています。現在は Windows x64、および Android 9 以降を搭載した arm64-v8a の横画面端末で動作します。Linux、macOS、iOS への対応は今後の予定です。

本プロジェクトは現在も開発中です。

操作方法については、[Gotepad ユーザーマニュアル](docs/user_manual.md)（現在は中国語）を参照してください。

## リリース版の入手

ビルド済みバージョンは、本リポジトリの [GitHub Releases](../../releases) ページで公開します。変更内容は[更新履歴](docs/version_log.md)を参照してください。プログラムは本プロジェクトのリリースページ、または信頼できる配布元からのみ入手してください。

- Windows x64 版は単体の `Gotepad.exe` として提供され、インストールは不要です。KataGo 解析機能を利用するには、デスクトップ版 KataGo の実行ファイル、モデル、設定を別途用意する必要があります。
- Android 版は arm64-v8a APK として提供され、Android 9 以降に対応します。手動でインストールする場合は、必要に応じてシステムの案内に従い、現在の提供元からのアプリのインストールを許可してください。

## <u>本プロジェクトに残された、数少ない人間の言葉</u>

- 以前から作りたかったものを実現する手助けをしてくれた Codex に感謝します。
- これは、囲碁を学ぶ子どものために保護者が作ったノートツールです。高度な工学的・デザイン的追求よりも、個人開発と実用上の利便性を中心にしています。
- 今後の更新もすべて、永久にオープンソースかつ無料で提供します。必要に合えば安心してご利用ください。
- ビルドに必要な本プロジェクト固有のファイルはすべて公開しています。
  - 各サードパーティライブラリの `third_party` 配下には `gotepad_info.txt` があり、バージョンや配置方法などを記録しています。
  - AI を利用した自動ビルドを推奨します。
- **重要:** 既存の SGF 資産を本ソフトウェアで編集する際は十分に注意し、事前にコピーを作成してください。
  - Gotepad は SGF に独自プロパティを書き込むため、他の SGF ソフトウェアとの互換性を損なう可能性があります。
  - Gotepad が対応するのは SGF 仕様の一部であり、未対応のプロパティが失われる場合があります。

## 主な機能

- 囲碁盤の基本操作：着手、石の取り上げ、元に戻す、置き石の配置と修正、手番色の切り替え、誤タップ防止、盤面操作のロックに対応します。
- 分岐棋譜管理：棋譜の移動と連続再生、石の検索、次の手の分岐順序変更・削除、本線のみの保持、縮小盤による棋譜ツリー全体の可視化に対応します。
- 変化図検討：任意の局面から一時的な変化図を作成し、手順の閲覧や巻き戻しを行い、検討分岐を残すか破棄するか選択できます。
- SGF の読み書き：ローカルファイル、システムクリップボード、OS の「このアプリで開く」機能から棋譜を読み込めます。対局情報、置き石ノード、分岐、局面タイトル、コメント、一般的な盤面マーク、Gotepad 独自データに対応し、不正な SGF を読み込んだ場合は防御的な検証と警告を行います。
- 棋譜ノート：同じ局面に複数階層のノートを保存し、連番アルファベット、三角、四角、丸、バツのマークを追加できます。閲覧用と出版用で異なる手数表示方式を設定できます。「フォーカス」モードでは、出版時の出力順に全ノートを直線的に閲覧しながら直接編集できます。
- 画像から局面を作成：Windows ではローカル画像を選択し、Android では撮影またはギャラリーから選択できます。OpenCV が盤と黒石・白石を認識し、画像の回転、四隅補正、再認識、交点ごとの手動修正を行えます。
- KataGo 解析：単一局面・継続解析、候補手と変化図、盤面上の追加候補数、勝率・目差曲線、棋譜全体の高速解析、探索量の追加、実戦手の劣化警告に対応します。Windows はユーザーが配置した外部エンジンを使用し、Android は OpenCL/Eigen バックエンドとモデルを内蔵するとともに、外部モデルも読み込めます。
- KataGo 人間模倣対局：AI の黒番・白番、現代風または AlphaGo 以前の棋風、模倣棋力、1 手あたりの探索量を選び、現在の棋譜の任意局面から対局を開始できます。一時対局では待ったが可能で、元の棋譜へ残すか破棄するかを選べます。
- 終局計算：中国ルールで KataGo を利用して各交点の所有を判定し、連結領域単位で結果を手動修正できます。双方の石数と地、コミ、勝敗の目数を表示します。
- PPTX 出版出力：選択した盤面、手数、マーク、ノートを、編集可能な B5 横向き教材としてレイアウトします。盤面画像は SVG ベクターまたは互換性を重視した PNG を選択できますが、Android は現在 SVG のみに対応します。
- 複数文書とカスタマイズ可能な UI：タブ、新規作成、保存、名前を付けて保存、テクスチャ切り替え、手数表示、着手音量、盤面幅、UI 拡大率、モバイル端末の安全マージンなどを設定できます。
- クロスプラットフォーム操作：Windows x64 と Android arm64-v8a に対応します。Android ではタッチによる拡大・移動、大きな UI、横画面方向への追従、システムファイルマネージャーからの SGF 起動に対応します。
- 中国語、日本語、韓国語、英語の UI を提供します。
- SGF 保存時には一時バックアップを使用し、上書き失敗による元ファイル破損の危険を軽減します。

## 画面プレビュー

### 棋譜ノートと盤面マーク

同じ局面に複数階層のノートを記録し、盤面上に連番アルファベット、三角、四角、丸、バツなどのマークを追加できます。

![棋譜ノートと盤面マーク](examples/screenshots/notes.jpg)

### KataGo 局面解析

解析パネルには候補手、勝率、目差、候補変化図を表示し、棋譜全体の解析曲線を描画できます。

![KataGo 局面解析](examples/screenshots/analysing.jpg)

### KataGo 人間模倣対局

人間模倣対局専用モデルを読み込み、自分と同程度の AI と対局できます。

![KataGo 人間模倣対局](examples/screenshots/playwithai.jpg)

### 終局計算

KataGo の所有判定と中国ルールを利用して終局を計算します。

![終局計算](examples/screenshots/counting.jpg)

### 写真・画像認識

画像または写真から局面を作成します。

![写真・画像認識](examples/screenshots/recognition.jpg)

### PPTX 教材出力

盤面、手数、マーク、ノートをレイアウトし、編集可能な PPTX 囲碁教材として出力できます。

![PPTX 囲碁教材出力](examples/screenshots/courseware.png)

### 多言語 UI

![多言語 UI](examples/screenshots/multi-language.jpg)

## プロジェクト構成

```text
src/          C++ コアエンジン、GoNotes データ層、Godot GDExtension
gotepad-gd/   Godot クライアントプロジェクト、シーン、スクリプト、画像素材
tests/        C++ テストおよびテスト棋譜
third_party/  サードパーティ依存関係の配置先とバージョン情報
docs/         プロジェクト文書
```

将来、別のデスクトップ・モバイル UI を追加できるよう、コアコードは特定の GUI 技術から可能な限り分離しています。現在は Windows と Android クライアントを重点的に保守し、Linux、macOS、iOS は今後の対象です。

## ビルド環境

- CMake 3.20 以降
- C++17 対応コンパイラ
- `godot-cpp` バインディング生成用の Python 3
- Godot 4.7.1 非 .NET 版
- Godot 4.7 API に対応する `godot-cpp`

本プロジェクトは次のサードパーティライブラリに依存します。

- [godot-cpp](https://github.com/godotengine/godot-cpp)：Godot GDExtension の C++ バインディング。
- [libsgfc++](https://github.com/herzbube/libsgfcplusplus)：SGF の読み込み、検証、保存。
- [miniz](https://github.com/richgel999/miniz)：PPTX 出力に必要な ZIP アーカイブ機能。
- [LunaSVG](https://github.com/sammycage/lunasvg)：PPTX 内の盤面 SVG を、互換性を重視した PNG へ変換します。
- [Noto CJK](https://github.com/notofonts/noto-cjk)：PPTX の中国語レイアウトに使用するゴシック体と明朝体。フォントファイルは OFL-1.1 に基づいて提供されます。
- [KataGo](https://github.com/lightvector/KataGo)：囲碁局面解析エンジン。デスクトップ版は外部プロセスを使用し、Android 版は内蔵解析バックエンドとしてコンパイルします。
- [Eigen](https://gitlab.com/libeigen/eigen)：Android 内蔵 KataGo の CPU バックエンド。
- [OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers)：Android 内蔵 KataGo OpenCL バックエンドのコンパイル依存関係。

サードパーティのソースコードは本リポジトリには含まれません。各ディレクトリの `gotepad_info.txt` に従って指定バージョンを入手し、対応する `third_party` サブディレクトリに配置してください。PPTX 用フォントは `third_party/fonts/noto-cjk` にあります。出力ファイルにはフォントが埋め込まれないため、レイアウトを維持する必要がある場合はシステムへフォントをインストールしてください。完全なフォントライセンスは同ディレクトリの `OFL.txt` にあります。

依存関係を準備した後、CMake で Godot 拡張をビルドできます。

```sh
cmake -S . -B build -DGODOTCPP_TARGET=template_debug
cmake --build build --target go_gdext
```

拡張は `gotepad-gd/bin` に出力されます。Godot 4.7.1 で `gotepad-gd/project.godot` を開くと、開発またはクライアントの実行を続けられます。

### Android のビルド

Android 版は現在 `arm64-v8a` のみを対象とし、Android 9（API 28）以降が必要で、横画面向けに設計されています。ビルド環境には次のものも必要です。

- JDK 17
- Android SDK
- Android NDK r28
- 上記環境を指す `JAVA_HOME`、`ANDROID_HOME`、`ANDROID_NDK_HOME` 環境変数

`third_party/katago` の説明に従って KataGo、Eigen、OpenCL Headers のソースを準備し、`gotepad-gd/assets/katago` に Git LFS 管理のモデルを用意した後、Android NDK で Android GDExtension、内蔵 Eigen バックエンド、分離実行される OpenCL バックエンドをクロスコンパイルし、Godot の Android カスタムビルドテンプレートで APK を出力します。現在の内蔵モデルは `g170e-b10c128-s1141046784-d204142634` で、KataGo g170 拡張学習による 10 block / 128 channel ネットワークです。g170 の学習に計算資源とデータを提供し、関連モデルデータを CC0 でパブリックドメインへ提供した Jane Street と KataGo 作者 David J. Wu（lightvector）、およびダウンロードミラーを提供した pachi プロジェクトに感謝します。Android は端末が公開する OpenCL GPU 実装を優先し、OpenCL が利用できない場合、初期化に失敗した場合、または解析サービスが異常終了した場合は Eigen CPU バックエンドへ自動的に切り替えます。APK に端末メーカーの OpenCL ドライバーは含まれません。

正式版 APK は、自分で作成して長期間安全に保管する release keystore で署名する必要があります。署名鍵を失うと、同じアプリとしてユーザーへ上書き更新を提供できなくなります。鍵やパスワードをリポジトリへコミットしないでください。JDK 17 の `keytool` を使用して対話形式で鍵を作成できます。

```powershell
keytool -genkeypair -v -keystore gotepad-release.jks -alias gotepad -keyalg RSA -keysize 4096 -validity 10000
```

生成した鍵はリポジトリ外に保存し、安全なバックアップを作成してください。ローカルの Godot Android Release 出力プリセットに keystore、alias、パスワードを設定します。署名パスや認証情報を含むローカル出力設定を公開しないでください。

### プラットフォームごとの違い

- Windows 版では、設定画面でローカルの KataGo 実行ファイル、モデル、設定を選択します。Android 版は内蔵バックエンドと内部設定を使用するため、実行ファイルや設定ファイルの指定は不要です。また、システムのファイル選択画面から標準の `.bin.gz` または `.txt.gz` 外部解析モデルを読み込み、いつでも内蔵モデルへ戻せます。人間模倣対局は別の Human SL モデルと独立した自動性能テスト結果を使用し、通常解析モデルの性能設定をそのまま流用できません。
- Android 版では、アプリ内のシステムファイル選択画面から SGF を読み込むほか、システムクリップボードの完全な SGF テキストを貼り付けたり、ファイルマネージャーや「このアプリで開く」に対応する他のアプリから Gotepad で直接開いたりできます。
- Android 版の PPTX 出力は SVG 盤面画像のみに対応し、PNG モードは現在利用できません。SVG 版は Microsoft 公式 PowerPoint アプリで閲覧・編集できます。WPS など一部の互換ソフトでは埋め込み SVG が表示されない場合があります。
- OpenCL バックエンドは初回実行時に現在の GPU 向けの調整が必要で、2 回目以降より起動に時間がかかる場合があります。継続解析は消費電力と発熱を増加させます。

## ライセンス

本プロジェクトは [MIT License](LICENSE) の下で提供されます。サードパーティプロジェクトには、それぞれのライセンスが引き続き適用されます。
