# Создание адреса Yandex Cloud Postbox и проверка владения доменом с помощью Terraform

В этом руководстве вы с помощью Terraform создадите [адрес](https://yandex.cloud/ru/docs/postbox/concepts/glossary#adress) в [Yandex Cloud Postbox](https://yandex.cloud/ru/docs/postbox/), а также добавите в [DNS-зону](https://yandex.cloud/ru/docs/dns/concepts/dns-zone) вашего домена необходимые [ресурсные записи](https://yandex.cloud/ru/docs/dns/concepts/resource-record) для подтверждения владения доменом и отправки писем.

Ресурсную запись для подтверждения владения доменом можно добавить в [Yandex Cloud DNS](https://yandex.cloud/ru/docs/dns/), если вы [делегировали](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating#delegate) домен, или у вашего регистратора домена.

Для работы с Yandex Cloud Postbox в руководстве используется API, совместимый с AWS SESv2, поэтому для создания и управления ресурсами Yandex Cloud Postbox используется Terraform-провайдер [AWS](https://github.com/hashicorp/terraform-provider-aws). Для управления всеми остальными ресурсами используется Terraform-провайдер [Yandex Cloud](https://github.com/yandex-cloud/terraform-provider-yandex).

Подготовка инфраструктуры для создания адреса с помощью Terraform описана в [практическом руководстве](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating), необходимые для настройки конфигурационные файлы `postbox-email-identity.tf` и `postbox-email-identity.auto.tfvars` расположены в этом репозитории.
