# hermes-agent-image

Hermes Agent に GitHub CLI・Opus・Edge TTS を追加したコンテナイメージです。
linux/amd64・linux/arm64 に対応します。

## 公開

Actions の **Build image** を手動実行し、`publish` を有効にします。
公開は main ブランチからのみ実行できます。
初回公開後、GitHub Packages 側でパッケージの Visibility を **Public** に変更してください。

`ghcr.io/eeekcct/hermes-agent-image:sha-<commit SHA>` と `latest` を公開します。
デプロイにはコミット SHA のタグか image digest を指定してください。

## 使用

Helm Chart の values に指定します。

```yaml
image:
  repository: ghcr.io/eeekcct/hermes-agent-image
  tag: sha-<commit SHA>

config:
  tts:
    provider: edge
```

gh・Opus・Edge TTS を導入する initContainer と、そのための共有ボリュームは不要です。
既存のデータ PVC、認証情報、`GH_CONFIG_DIR` は引き続き使用できます。
STT（文字起こし）の設定は別途必要です。

## ローカルビルド

```sh
docker buildx build --load -t hermes-agent-image:local .
docker run --rm --user 10000:10000 \
  -e HOME=/tmp/hermes-image-check -e HERMES_HOME=/tmp/hermes-image-check \
  --entrypoint /usr/local/libexec/hermes-image-smoke-test \
  hermes-agent-image:local
```

Hermes のバージョンを変更する場合は、Dockerfile のベースイメージ・digest と、
`scripts/build-dependencies.sh` の依存構築手順を更新先の Dockerfile に合わせて確認します。
GitHub CLI のバージョン変更時は、両アーキテクチャの SHA256 も更新します。
