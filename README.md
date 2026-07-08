# Создание адреса Yandex Cloud Postbox и проверка владения доменом с помощью Terraform

В этом руководстве вы с помощью Terraform создадите [адрес](https://yandex.cloud/ru/docs/postbox/concepts/glossary#adress) в [Yandex Cloud Postbox](https://yandex.cloud/ru/docs/postbox/), а также добавите в [DNS-зону](https://yandex.cloud/ru/docs/dns/concepts/dns-zone) вашего домена необходимые [ресурсные записи](https://yandex.cloud/ru/docs/dns/concepts/resource-record) для подтверждения владения доменом и отправки писем.

Ресурсную запись для подтверждения владения доменом можно добавить в [Yandex Cloud DNS](https://yandex.cloud/ru/docs/dns/), если вы [делегировали](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating#delegate) домен, или у вашего регистратора домена.

Для работы с Yandex Cloud Postbox в руководстве используется API, совместимый с AWS SESv2, поэтому для создания и управления ресурсами Yandex Cloud Postbox используется Terraform-провайдер [AWS](https://github.com/hashicorp/terraform-provider-aws). Для управления всеми остальными ресурсами используется Terraform-провайдер [Yandex Cloud](https://github.com/yandex-cloud/terraform-provider-yandex).

Подготовка инфраструктуры для создания адреса с помощью Terraform описана в [практическом руководстве](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating), необходимые для настройки конфигурационные файлы `postbox-email-identity.tf` и `postbox-email-identity.auto.tfvars` расположены в этом репозитории.

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
