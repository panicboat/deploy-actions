# Stack Configuration Design

## Intent

同じ stack のパスと属性を一つの定義で確認できる設定モデルを提供する。プロダクト間で属性を共有する場合と、独立した属性を持つ場合を同じ形式で表現する。

設定の破壊的変更を許容する。新しいモデルを読み込み、変更検出・環境選択・matrix 生成・設定表示が直接利用する。旧形式への変換や互換用のアクセス方法は提供しない。

## Configuration

トップレベルには必須の `stacks` だけを置く。`stacks` は空でない配列とする。stack 定義のフィールドは `name`、`id`、`paths`、`environments`、`attributes`、`exclude` に限る。トップレベルと stack 定義の未知のフィールドは設定エラーとする。

```yaml
stacks:
  - name: terragrunt
    id: aws
    paths:
      - "dystopia/{service}/aws/{environment}"
      - "system-components/{service}/infrastructure/aws/{environment}"
    environments:
      develop:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::111111111111:role/plan-develop
        iam_role_apply: arn:aws:iam::111111111111:role/apply-develop
      production:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::111111111111:role/plan-production
        iam_role_apply: arn:aws:iam::111111111111:role/apply-production
    exclude:
      - service: demo
        environment: production

  - name: container
    paths:
      - "dystopia/{service}"
      - "system-components/{service}"
    attributes:
      repository: registry.example.com/app
```

### Stack Identity

`name` は処理の種類を表す空でない文字列である。`id` は設定単位を識別する任意の空でない文字列である。`id` を省略した定義は、読み込み時に `name` を識別子として確定する。

識別子は設定全体で一意にする。同じ種類の stack を複数定義する場合は、一意な識別子を持たせる。属性はその定義から直接取得し、別の識別子や種類名を探索しない。

### Paths

`paths` は完全なディレクトリパターンの空でない配列である。各パターンはリポジトリルートからの相対パスとし、`{service}` を含める。`root` と `directory` の分割は持たない。

各パターンの実在するディレクトリをすべて対象にする。同じサービス名のディレクトリが複数プロダクトに存在する場合も、それぞれ別の matrix 行になる。パターンの記載順による優先順位は設けない。

`{service}` と `{environment}` に加え、`{team}` などの任意の placeholder を利用できる。placeholder 名は `[a-z_][a-z0-9_]*` とし、抽出値は一つのパス要素内に収まる。同じ名前が繰り返される場合は同じ値に一致する。

### Environment Attributes

`environments` のキーが環境名であり、その値が当該環境の属性である。キーは空でない文字列、値は属性のマップとする。環境名は一つのパス要素として利用できる値とし、`/` を含む値と、`.` または `..` そのものを拒否する。環境に属性が不要なら空のマップを指定できる。

`environments` を持つ stack は、定義した環境だけで実行する。全体の環境一覧は各 stack の環境名の和集合から導出する。全体の環境一覧を設定には登録せず、環境属性の識別には `environments` のキーを使う。

実行単位は環境の定義で決まる。環境を持つ stack のパスに `{environment}` がなくても、そのディレクトリを環境ごとに異なる属性で実行できる。

### Shared Attributes

`environments` を持たない stack は環境共通である。属性は任意の `attributes` マップに置き、省略時は空のマップとして扱う。環境選択数にかかわらず、実在するディレクトリごとに一度実行する。

`attributes` と `environments` は併用しない。環境共通の属性と環境属性を暗黙にマージする規則は設けない。環境共通の stack のパスに `{environment}` がある場合は設定エラーとする。

### Product Boundaries

属性セットを共有するプロダクトのパスは一つの stack 定義に集める。除外規則はその定義内で管理し、placeholder の条件で対象を絞り込める。属性セットや設定の管理単位が独立する場合は、同じ `name` を持つ別の定義にする。

```yaml
stacks:
  - name: terragrunt
    id: dystopia-aws
    paths:
      - "dystopia/{service}/aws/{environment}"
    environments:
      develop:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::111111111111:role/plan

  - name: terragrunt
    id: system-components-aws
    paths:
      - "system-components/{service}/infrastructure/aws/{environment}"
    environments:
      develop:
        aws_region: us-west-2
        iam_role_plan: arn:aws:iam::222222222222:role/plan
```

一部のプロダクトだけで共有する場合は、その範囲のパスを同じ定義にまとめる。属性の一部だけが共通の場合は、独立した各定義に値を明記する。属性の継承・参照・共通定義の解決機構は設けない。

### Target Exclusions

各 stack の任意の `exclude` に、除外条件のマップを並べる。省略時は空の配列として扱う。各規則はその stack 定義の対象だけに作用する。一つのマップ内の条件はすべて一致する必要があり、配列内の規則のいずれかが一致した対象を除外する。値は完全一致で照合し、省略したキーは条件に含めない。

条件のキーには固定の `service`・`environment` と、当該 stack の `paths` に定義した任意の placeholder 名を使える。`service` と `environment` の指定はそれぞれ任意であり、各規則に少なくとも一つのキーを要求する。空のマップと、許可されたキー以外の指定は設定エラーとする。

`service` と `environment` は実行対象として確定した値を照合する。パスに `{environment}` がなくても環境別の除外ができる。任意の placeholder は、照合したパスから抽出した値を使う。当該パスから条件のキーに対応する値を抽出できなかった場合は、その規則には一致しない。

条件値は空でない文字列とし、`/` を含む値と、`.` または `..` そのものを拒否する。`service` はさらに `.` で始まる値を拒否する。環境を持つ stack では `environment` に当該 stack に定義された環境名を指定する。環境共通の stack では `environment` に `null` だけを指定でき、条件から省略することもできる。`null` を許容するキーは `environment` だけとする。サービスや任意の placeholder の値がまだディレクトリに存在しない場合も、規則の定義は有効である。

```yaml
stacks:
  - name: terragrunt
    id: aws
    paths:
      - "{team}/{service}/aws/{environment}"
    environments:
      develop: {}
      production: {}
    exclude:
      - team: platform
        service: demo
        environment: production
      - team: sandbox
```

この例では、`platform` の `demo` の `production` と、`sandbox` のすべてのサービス・環境を当該 stack から除外する。`service` だけを指定するとそのサービスの全環境、`environment` だけを指定するとその環境の全サービスを当該 stack から除外する。

任意のキーの許可範囲は当該 stack のすべての `paths` から集める。例えば `{team}` を含むパスと含まないパスを併記できるが、`team` を条件に持つ規則は後者には一致しない。リテラルのディレクトリ名から placeholder の値を推測しない。プロダクト名を条件に使うには、パスに `{product}` として定義する。

設定全体のサービス除外、除外理由や種別、パスによる別の除外形式は設けない。サービス一覧は実在するパスから取得し、設定には登録しない。

## Responsibilities

| Component | Responsibility |
|---|---|
| `ConfigClient` | 設定ファイルを読み、YAML を解析して設定モデルへ渡す。ファイル読み込みと YAML 構文のエラーを伝える。 |
| `WorkflowConfig` | スキーマと設定内の整合性を一か所で検証し、stack 定義・環境名・当該 stack の確定した値に基づく除外判定を提供する。 |
| `PatternMatcher` | placeholder の文法、照合、展開、抽出を扱う。プロダクトや stack の属性を判断しない。 |
| `DetectChangedServices` | 各 stack のパスに変更ファイルを照合し、環境名と任意の placeholder を解決して、除外されない照合があるサービスをラベル対象にする。 |
| `DetermineTargetEnvironment` | 環境選択を導出された環境一覧と照合する。 |
| `GenerateMatrix` | stack の環境と各パスから実在する実行対象を列挙し、除外規則を適用してその定義の属性を渡す。 |
| Config manager | 同じ設定モデルを使って検証結果・stack・環境・属性・除外規則を表示する。 |

各利用側は `stacks` を直接扱う。root ごとの convention 配列を中間表現として組み立てない。属性と除外規則は読み込んだ定義内で完結し、プロバイダー固有の知識を設定モデルに持ち込まない。変更検出と matrix 生成は同じ除外判定を利用する。

## Runtime Flow

1. 設定ファイルを読み、スキーマと設定内の整合性を検証する。成功時だけ検証済みモデルを利用側へ渡す。
2. 環境指定を検証する。指定省略時は定義された全環境を選択し、重複した指定は一つにまとめる。未知の環境名があれば処理を失敗させる。
3. ラベルのサービス指定を確認する。通常のサービスラベルでは指定した名前でパスを照合し、`deploy:all` では実在するパスからすべてのサービスを取得する。
4. stack ごとに対象環境を決める。環境を持つ stack は定義された環境と選択された環境の共通部分を使い、環境共通の stack は環境値を `null` として一度処理する。
5. 各パスの実在するディレクトリを列挙し、サービス名と環境名を確認する。任意の placeholder に複数の値が一致する場合も各ディレクトリを対象にする。存在しないパスは対象を生成しない。
6. 各対象のサービス名・環境名・任意の placeholder の抽出値を当該 stack の除外規則と照合し、一致した対象を除く。通常のサービスラベルと `deploy:all` の双方で同じ規則を適用する。
7. 各対象へ、その stack 定義の環境属性または環境共通の属性と、パスから抽出した値を渡す。対象の一意性を確認した配列が matrix 生成の完了条件となる。

環境共通の stack だけを持つ設定も有効である。環境指定を省略した場合は空の環境一覧から環境共通の対象を生成できる。明示的な環境指定は、定義された環境名であることを要求する。

変更検出は各 `paths` が指すディレクトリとその配下を対象にする。サービス全体の変更を検出するには、`dystopia/{service}` のようにサービスディレクトリを指すパスを stack に定義する。`{environment}` を含むパスで定義外の環境を抽出した場合は、その照合をラベル対象にしない。

変更ファイルが照合したパスからサービス名と任意の placeholder の値を抽出し、環境名を解決して除外規則を適用する。環境を持つ stack のパスに `{environment}` がない場合は、その stack の定義された環境ごとに判定する。環境共通のパスは環境値を `null` として判定する。条件のキーに対応する抽出値がない場合は、その規則には一致しない。除外されない照合が一つでもあればサービスラベルを生成し、除外された照合しかない場合は生成しない。

## Matrix

matrix の固定キーは `service`、`environment`、`stack`、`stack_id`、`working_directory` とする。`stack` は `name`、`stack_id` は確定した識別子、`working_directory` は解決した相対パスである。環境共通の対象では `environment` が `null` になる。

属性と任意の placeholder の抽出値はトップレベルへ展開する。`service` と `environment` の抽出値は固定フィールドに反映し、追加のキーとして扱わない。属性値の型を変換しない。

`stack_convention_root` は出力しない。完全なパスから別のルート値を推測する規則は設けない。

実行対象の識別には `service`、`stack_id`、`environment`、`working_directory` を使う。これらが同じ対象は一行にまとめる。同じ対象で異なる placeholder の抽出結果が得られた場合は、曖昧な設定として失敗させる。異なるパスや独立した識別子の対象は別行にする。

## Validation and Errors

設定モデルで以下を検証する。

- トップレベルと stack 定義の構造と許可されたフィールド。
- 空でない `name`、指定された `id` の型、設定全体での識別子の一意性。
- 空でない `paths` 配列と文字列のパターン。絶対パスと親ディレクトリへ移動する要素は拒否する。`.` 要素と末尾の `/` は相対パスとして正規化する。
- 各パターンの `{service}`、placeholder の文法、同名 placeholder の一致規則。
- `environments` が指定された場合の空でないマップ、環境名と属性マップの型。`environments: {}` は設定エラーとする。
- `attributes` の型、`environments` との併用、環境共通のパスでの `{environment}` 使用。
- 属性キーは空でない文字列であり、matrix の固定キーと衝突しないこと。
- 任意の placeholder 名が matrix の固定キーや当該 stack の属性キーと衝突しないこと。環境属性のキーはその stack の全環境から収集する。
- `exclude` の配列と各規則の空でないマップ。キーが `service`・`environment` または当該 stack の `paths` の placeholder 名であること。
- 除外条件の値の型とパス要素の制約。環境を持つ stack で指定した除外条件の環境名が当該 stack に定義されていること。環境共通の stack で指定した除外条件の環境値が `null` であること。

属性の必須チェックと、環境間で属性キーを揃える検証は行わない。必要な属性の判断は利用側の workflow または action が担う。

設定エラーは設定内の位置と理由を含めて利用側へ伝える。ファイル・YAML・ディレクトリ列挙のエラーや矛盾した抽出結果は失敗として返し、途中の matrix は成功結果として返さない。該当ディレクトリが存在しない場合は正常な空結果として扱う。

## Removal Scope

新しい形式の利用側を揃え、以下の設定モデルに関係する経路を削除する。

- トップレベルの `environments` と `stack_conventions`、サービス配下の `stack_conventions` の読み込み。
- `services` の登録、`exclude_from_automation`、`exclusion_config` と、全体のサービス除外一覧・理由・種別の取得や検証。
- `required_attributes` とその取得・型検証・必須キー検証。
- `stack_conventions*`、`directory_stacks`、root の取得と推測など、旧構造を公開するメソッド。
- 属性を識別子から種類名へ探し直す処理と、最初の convention や最初のパスだけを採用する処理。
- 環境共通の対象に空の属性を固定して渡す処理。
- 設定の読み込み失敗時に環境一覧を既定値で補う処理。
- 設定の各利用側に分散したスキーマ検証と、特定のプロバイダーの属性だけを表示する設定 CLI の処理。
- 登録したサービスの一覧と全体のサービス除外一覧を表示する CLI コマンド、およびその統計表示。
- 全体のサービス除外一覧を前提とする内部の `EXCLUDED_SERVICES` と `HAS_EXCLUDED_SERVICES`、および対応する内部出力と表示。
- 新しいモデルを利用する箇所から呼ばれなくなる補助処理、旧形式を前提とする fixture と期待値。

許可するフィールドを検証することで旧形式を拒否し、旧形式専用の変換器・アダプター・二重の読み込み経路は作らない。設定例、テンプレート、README、CLI 表示、テストの fixture は同じスキーマに揃える。変更履歴を扱う文書は現在の設定例として参照しない。

## Alternatives

root ごとのグループ内へ属性を移す形式は、同じ stack が複数プロダクトに存在すると定義と属性の共有範囲が分散する。stack を設定単位とし、パスを列挙する形式なら、共有する範囲を一つの定義で確認できる。

`root` と `directory` を別フィールドとして持つ形式は、実行パスを確認する際に二つの値を結合する必要がある。完全なパターンを使うことで、実行パスを直接確認できる。

属性の共通定義や継承を導入すると、属性値を確認するために別の定義と上書き順序を追う必要がある。複数パスで共有する定義と、独立した識別子の定義を使い分けることで共有範囲を明示する。

パスによる除外は、環境名がパスに含まれない stack で環境別の対象を指定できない。確定したサービス名と環境名を条件に使うことで、ディレクトリ構成と除外対象を独立させる。任意の placeholder も条件に使うことで、パスに定義した team や product の単位で除外できる。

除外のキーを固定すると、team や product を使う構成ごとにスキーマを拡張する必要がある。当該 stack の placeholder 名から許可するキーを導出することで、構成で定義した単位を使え、未定義のキーによる誤記も検出できる。

## Verification Criteria

実装の完了条件は、新しいモデルに対して以下の振る舞いをテストで確認することである。

1. プロダクトごとに異なるパスが同じ属性を共有し、実在する各パスが対象になる。
2. 同じ `name` の独立した定義が、各識別子の属性を持つ対象になる。
3. 定義した環境だけを対象にし、未定義の環境でディレクトリが存在しても対象にしない。
4. 環境共通の対象が、複数環境選択時と環境共通だけの設定の双方で、各ディレクトリにつき一度生成される。その属性も matrix に渡る。
5. 環境を持つ stack のパスに `{environment}` がなくても、環境ごとの対象と属性が得られる。
6. 同名サービスの複数プロダクト、任意の placeholder の複数一致、重複したパスが、対象の識別規則どおりに処理される。
7. サービスだけ、環境だけ、両方の指定を受け付け、指定した条件だけで当該 stack の対象を除外する。環境名がパスにない構成でも環境別に除外できる。
8. 任意の placeholder だけの条件と、固定キーを組み合わせた条件を受け付ける。一つのマップ内は AND、規則の配列は OR で一致し、条件の抽出値がないパスは一致しない。別の stack の placeholder は条件のキーとして許可しない。
9. 環境共通の対象をサービス名や任意の placeholder で除外でき、`environment: null` の指定と環境条件の省略の双方を受け付ける。変更検出と matrix 生成の双方で同じ規則が作用する。
10. 変更検出は有効な照合があるサービスだけをラベル対象にする。除外された照合しかない場合と、除外されない環境・stack・任意の placeholder の照合もある場合を区別する。
11. `deploy:all` がサービスの明示登録を要求せず、実在するパスから得られたサービス名・環境名・任意の placeholder の値に除外規則を適用する。
12. 新しいスキーマの型、識別子重複、フィールド混在、placeholder 衝突、矛盾した抽出結果を検出する。除外規則の空のマップ・未定義のキー・未定義の環境・不正な値の型・環境共通の対象への非 null の環境指定も検出する。
13. 旧形式と廃止したフィールドを拒否する。属性キーが環境ごとに異なる設定と、必須キーの宣言がない設定を受け付ける。
14. matrix に固定キー・属性・抽出値が正しく入り、ルート由来の出力を持たない。
15. Config manager の検証・表示・環境一覧・サービス診断・テンプレートが同じ設定モデルを利用する。

実装時には対象のテストと全体の RSpec を実行し、サンプル設定を Config manager で検証する。旧モデルの経路と互換コードが利用側に残っていないことを検索と差分レビューで確認する。
