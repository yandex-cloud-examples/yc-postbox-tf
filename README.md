# Создание адреса Yandex Cloud Postbox и проверка владения доменом с помощью Terraform

В этом руководстве вы с помощью Terraform создадите адрес в [Yandex Cloud Postbox](https://yandex.cloud/ru/docs/postbox/), а также добавите в DNS-зону вашего домена необходимые ресурсные записи для подтверждения владения доменом и отправки писем.

Ресурсную запись для подтверждения владения доменом можно добавить в [Yandex Cloud DNS](https://yandex.cloud/ru/docs/dns/), если вы делегировали домен, или у вашего регистратора домена.

Для работы с Yandex Cloud Postbox в руководстве используется API, совместимый с AWS SESv2, поэтому для создания и управления ресурсами Yandex Cloud Postbox используется провайдер AWS. Для управления всеми остальными ресурсами используется провайдер Yandex Cloud.

Подготовка инфраструктуры для создания адреса с помощью Terraform описана в [практическом руководстве](https://yandex.cloud/ru/docs/postbox/tutorials/domain-identity-creating), необходимые для настройки конфигурационные файлы `postbox-email-identity.tf` и `postbox-email-identity.auto.tfvars` расположены в этом репозитории.
