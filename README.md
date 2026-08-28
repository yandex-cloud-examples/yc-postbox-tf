# Создание адреса Yandex Cloud Postbox и проверка владения доменом с помощью Terraform

В этом руководстве вы с помощью Terraform создадите [адрес](https://yandex.cloud/ru/docs/postbox/concepts/glossary#adress) в [Yandex Cloud Postbox](https://yandex.cloud/ru/docs/postbox/), а также добавите в [DNS-зону](https://yandex.cloud/ru/docs/dns/concepts/dns-zone) вашего домена необходимые [ресурсные записи](https://yandex.cloud/ru/docs/dns/concepts/resource-record) для подтверждения владения доменом и отправки писем.

Ресурсную запись для подтверждения владения доменом можно добавить в [Yandex Cloud DNS](https://yandex.cloud/ru/docs/dns/), если вы [делегировали](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating#delegate) домен, или у вашего регистратора домена.

Для работы с Yandex Cloud Postbox в руководстве используется API, совместимый с AWS SESv2, поэтому для создания и управления ресурсами Yandex Cloud Postbox используется Terraform-провайдер [AWS](https://github.com/hashicorp/terraform-provider-aws). Для управления всеми остальными ресурсами используется Terraform-провайдер [Yandex Cloud](https://github.com/yandex-cloud/terraform-provider-yandex).

Подготовка инфраструктуры для создания адреса с помощью Terraform описана в [практическом руководстве](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating).

## Способы подписи DKIM

Yandex Cloud Postbox поддерживает два способа подписи писем с помощью [DKIM](https://yandex.cloud/ru/docs/postbox/concepts/authentication#dkim). Выберите подходящий вариант — в соответствующей папке находятся необходимые для настройки конфигурационные файлы `postbox-email-identity.tf` и `postbox-email-identity.auto.tfvars`.

* [EasyDKIM](EasyDKIM/) — ключи DKIM генерирует и хранит сам Yandex Cloud Postbox. Вы добавляете в DNS-зону две CNAME-записи, которые ссылаются на публичные ключи, выпущенные Postbox. Ключи могут автоматически ротироваться без изменения DNS-записей. Это рекомендуемый способ.
* [BYODKIM](BYODKIM/) (Bring Your Own DKIM) — вы генерируете пару ключей DKIM самостоятельно, передаёте приватный ключ в Postbox и добавляете в DNS-зону одну TXT-запись с публичным ключом. Подходит, если у вас уже есть собственные ключи DKIM или их выдаёт внешняя система.

В обоих примерах создаётся одинаковая базовая инфраструктура (сервисный аккаунт, роль `postbox.admin`, статический ключ доступа и адрес в Yandex Cloud Postbox), различается только настройка DKIM и добавляемые DNS-записи.

## Пулы выделенных IP

Если вашему тенанту выданы выделенные IP-адреса, их можно сгруппировать в пул и отправлять письма только с адресов этого пула — например, чтобы развести по разным адресам транзакционные и рекламные рассылки.

* [DedicatedIPPools](DedicatedIPPools/) — создание пула выделенных IP, перемещение в него адресов тенанта и настройка конфигурации отправки, привязанной к пулу.

Выделенные IP-адреса выдаются тенанту отдельно, Terraform их не создаёт: пример только раскладывает по пулам уже выданные адреса.

## FAQ

### При `terraform apply` провайдер AWS не может найти учётные данные (`failed to refresh cached credentials, no EC2 IMDS role found`)

Ключ доступа (`access_key` и `secret_key`) для провайдера AWS создаётся динамически в этой же конфигурации — ресурсом `yandex_iam_service_account_static_access_key`. На этапе `plan` значения ключа ещё неизвестны, и Terraform иногда пытается настроить провайдер AWS до того, как ключ будет создан. Не найдя учётные данные в параметрах провайдера, AWS проходит по цепочке источников до метаданных инстанса (IMDS) и завершается ошибкой. Опция `skip_credentials_validation` в этом случае не помогает, так как проверять ещё нечего.

Чтобы дать провайдеру запасной источник учётных данных на время `plan`, задайте перед запуском Terraform фиктивные переменные окружения:

```bash
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
terraform apply
```

Переменные окружения имеют более низкий приоритет, чем параметры в блоке `provider "aws"`, поэтому на этапе `apply` — когда ключ уже создан (это гарантирует `depends_on` в ресурсе `aws_sesv2_email_identity`) — будут использованы настоящие учётные данные сервисного аккаунта. Фиктивные значения нужны только для инициализации провайдера на этапе `plan`.

### При `terraform apply` провайдер Yandex Cloud требует явной настройки (`Provider ... requires explicit configuration`)

Ни в одном из примеров нет блока `provider "yandex" {}`: провайдер берёт учётные данные из окружения. Если их там нет, `terraform apply` падает ещё до первого обращения к Postbox:

```text
Error: Invalid provider configuration

Provider "registry.terraform.io/yandex-cloud/yandex" requires explicit
configuration. Add a provider block to the root module and configure the
provider's required arguments as described in the provider documentation.

Error: Failed to configure

  with provider["registry.terraform.io/yandex-cloud/yandex"],
  on <empty> line 0:
  (source code not available)

one of 'token' or 'service_account_key_file' should be specified; if you
are inside compute instance, you can attach service account to it in order
to authenticate via instance service account
```

Задайте IAM-токен перед запуском Terraform:

```bash
export YC_TOKEN=$(yc iam create-token)
```

Это отдельная проблема от фиктивных AWS-ключей выше: там речь о ключе AWS, которого ещё нет, потому что эта же конфигурация его и создаёт, здесь — об обычных учётных данных провайдера Yandex Cloud, которые обязательны всегда.

### После обновления примера `terraform plan` хочет удалить `yandex_resourcemanager_folder_iam_binding` и создать `yandex_resourcemanager_folder_iam_member`

В примерах [EasyDKIM](EasyDKIM/) и [BYODKIM](BYODKIM/) роль `postbox.admin` раньше выдавалась ресурсом `yandex_resourcemanager_folder_iam_binding`, а теперь выдаётся ресурсом `yandex_resourcemanager_folder_iam_member`. `binding` управляет списком всех исполнителей роли в каталоге целиком, `member` — только одной выдачей роли одному субъекту. Благодаря этому все три примера можно применить в одном каталоге: они больше не вычёркивают сервисные аккаунты друг друга из роли `postbox.admin`.

Если вы уже применяли EasyDKIM или BYODKIM, в вашем состоянии Terraform лежит ресурс по старому адресу — `yandex_resourcemanager_folder_iam_binding.postbox-admin["postbox.admin"]`. После обновления файлов примера `terraform plan` покажет удаление старого ресурса и создание нового, а провайдер предупредит, чем это грозит:

```text
Plan: 1 to add, 0 to change, 1 to destroy.

Warning: Role "postbox.admin" will be removed from 2 subject(s) of
yandex_resourcemanager_folder_iam_binding "b1g..."

Applying this change calls SetAccessBindings and removes role "postbox.admin"
from ALL of its current subjects that are not listed in this resource's
"members", including subjects granted outside of Terraform (via the
corresponding *_iam_member resource, the console, CLI or API).
```

Применять такой план нельзя. Это два разных адреса ресурса, между которыми нет зависимости, поэтому порядок операций Terraform не гарантирует, — а работают они с одной и той же выдачей роли `postbox.admin` вашему сервисному аккаунту. Если создание выполнится раньше удаления, удаление снимет роль, которую создание только что выдало. Вдобавок удаление `binding` вызывает `SetAccessBindings` и снимает `postbox.admin` со всех остальных субъектов каталога — в том числе с тех, кому роль выдана вне этой конфигурации. В состоянии при этом останется `yandex_resourcemanager_folder_iam_member`, как будто роль выдана, а у сервисного аккаунта её не будет: ошибка прав от Postbox проявится только при следующем запуске.

Перенесите ресурс в состоянии вручную, не давая Terraform удалить `binding`. Команда `terraform state rm` работает только с файлом состояния и к API не обращается, поэтому роль она не снимает:

```bash
terraform state rm 'yandex_resourcemanager_folder_iam_binding.postbox-admin["postbox.admin"]'
terraform import yandex_resourcemanager_folder_iam_member.postbox-admin \
    'b1g...,postbox.admin,serviceAccount:aje...'
```

Одинарные кавычки вокруг адреса `binding` обязательны: это экземпляр `for_each` с ключом `"postbox.admin"`, и без кавычек скобки и кавычки съест командная оболочка. Идентификатор для импорта `member` состоит из трёх частей через запятую: ID каталога, роль и субъект в формате `serviceAccount:<ID сервисного аккаунта>`. ID сервисного аккаунта можно посмотреть командой `terraform state show yandex_iam_service_account.postbox` или `yc iam service-account get postbox-admin`.

После импорта `terraform plan` покажет одно пересоздание `yandex_resourcemanager_folder_iam_member.postbox-admin`: атрибут `sleep_after` при импорте не восстанавливается, а изменяется он только пересозданием. Это пересоздание безопасно — в отличие от удаления `binding`, оно затрагивает ровно одну выдачу роли: снимает её и тут же выдаёт заново тому же сервисному аккаунту. Примените его обычным `terraform apply`, после чего `terraform plan` станет пустым.

Убедиться, что роль осталась на месте, можно так:

```bash
yc resource-manager folder list-access-bindings b1g...
```
