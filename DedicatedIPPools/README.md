# Пул выделенных IP в Yandex Cloud Postbox

Пример создаёт [пул выделенных IP-адресов](https://yandex.cloud/ru/docs/postbox/concepts/dedicated-ip), перемещает в него выделенные IP-адреса вашего тенанта и создаёт конфигурацию отправки, привязанную к этому пулу. Письма, отправленные с указанием этой конфигурации, уходят только с адресов пула.

## Что создаётся

* сервисный аккаунт `postbox-pools-admin` с ролью `postbox.admin` и статический ключ доступа к нему — по ним работает провайдер AWS;
* пул выделенных IP — ресурс `aws_sesv2_dedicated_ip_pool`;
* привязка каждого адреса из переменной `dedicated_ips` к пулу — ресурс `aws_sesv2_dedicated_ip_assignment`;
* конфигурация отправки, ограничивающая отправку этим пулом, — ресурс `aws_sesv2_configuration_set`.

## Предусловия

1. **Выделенные IP-адреса уже выданы вашему тенанту.** Terraform их не создаёт: он только раскладывает по пулам уже выданные адреса. Посмотреть список можно так:

    ```bash
    aws sesv2 get-dedicated-ips \
        --endpoint-url https://postbox.cloud.yandex.net --region ru-central1
    ```

    По умолчанию все адреса лежат в пуле `ses-default-dedicated-pool`. Адрес, перемещённый в ваш пул, из общего пула уходит.

2. **Домен для отправки уже подтверждён** — например, примером [EasyDKIM](../EasyDKIM/) или [BYODKIM](../BYODKIM/). Пул сам по себе не даёт права отправлять письма.

3. Установлены [Terraform](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-quickstart) и [AWS CLI](https://yandex.cloud/ru/docs/postbox/tools/aws-cli).

## Применение

1. Заполните `postbox-dedicated-ip-pool.auto.tfvars`:

    ```hcl
    folder_id              = "b1g..."
    pool_name              = "mypool"
    dedicated_ips          = ["203.0.113.10"]
    configuration_set_name = "myconfigset"
    ```

    Пустой список `dedicated_ips` допустим: пул будет создан без адресов. Отправлять через него не получится — см. раздел «Проверка».

2. Задайте учётные данные провайдера Yandex Cloud. В конфигурации нет блока `provider "yandex" {}`, поэтому провайдер берёт их из окружения; без них `terraform apply` падает ещё до обращения к Postbox:

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

    ```bash
    export YC_TOKEN=$(yc iam create-token)
    ```

3. Примените конфигурацию:

    ```bash
    export AWS_ACCESS_KEY_ID=dummy
    export AWS_SECRET_ACCESS_KEY=dummy
    terraform init
    terraform apply
    ```

    Фиктивные переменные окружения нужны на этапе `plan`, пока статический ключ доступа ещё не создан. Подробнее — в разделе [FAQ](../README.md#faq) корневого README. Это отдельная проблема от `YC_TOKEN` из шага 2: там речь об обычных учётных данных провайдера Yandex Cloud, которые просто обязательны, здесь — о ключе AWS, которого ещё нет, потому что эта же конфигурация его и создаёт.

## Проверка

Отправьте письмо, указав созданную конфигурацию отправки:

```bash
aws sesv2 send-email \
    --endpoint-url https://postbox.cloud.yandex.net --region ru-central1 \
    --from-email-address sender@example.com \
    --destination ToAddresses=success@simulator.pstbx.ru \
    --configuration-set-name myconfigset \
    --content '{"Simple":{"Subject":{"Data":"Test"},"Body":{"Text":{"Data":"Test"}}}}'
```

Если в пуле есть хотя бы один адрес, ответом будет идентификатор письма:

```json
{"MessageId": "DKZT7OQLXZ9G.3COMUAY2ZKJMK@ingress1-vla"}
```

Если пул пуст, отправка отклоняется сразу, без попытки отправить письмо с общих адресов:

```text
aws: [ERROR]: An error occurred (NotFoundException) when calling the SendEmail operation: IP Pool is not valid or no available IPs found in the pool.
RequestID: 24467a92-719a-4b35-ad93-79027d23636a
```

Проверить, что адрес действительно лежит в вашем пуле:

```bash
aws sesv2 get-dedicated-ip --ip 203.0.113.10 \
    --endpoint-url https://postbox.cloud.yandex.net --region ru-central1
```

## На что обратить внимание

**Имя пула в конфигурации отправки берётся из атрибута ресурса.** В примере написано `sending_pool_name = aws_sesv2_dedicated_ip_pool.example.pool_name`, а не `var.pool_name`. Именно так Terraform понимает, что конфигурация отправки зависит от пула, и при `terraform destroy` удаляет её раньше пула. Если заменить ссылку на переменную, порядок удаления станет произвольным и `destroy` может завершиться ошибкой на пуле, к которому ещё привязаны адреса и конфигурация отправки.

**Блок `delivery_options` указывайте всегда.** Конфигурация отправки, объявленная без него, приводит к бесконечному расхождению: Terraform каждый раз показывает удаление блока, а после `apply` `terraform plan` снова оказывается непустым.

**Смена набора адресов в пуле не пересоздаёт пул.** Ключом `for_each` служит сам адрес, поэтому добавление и удаление адресов затрагивает только соответствующие привязки.

**Пул поддерживает теги.** Добавьте в ресурс `aws_sesv2_dedicated_ip_pool` аргумент `tags = { ... }`, если нужно. Их изменение применяется на месте и пул не пересоздаёт.

## Импорт существующих ресурсов

Если пул и конфигурация отправки уже созданы вручную, их можно перенести под управление Terraform:

```bash
terraform import aws_sesv2_dedicated_ip_pool.example mypool
terraform import 'aws_sesv2_dedicated_ip_assignment.example["203.0.113.10"]' '203.0.113.10,mypool'
terraform import aws_sesv2_configuration_set.example myconfigset
```

| Ресурс | Идентификатор для импорта |
|---|---|
| `aws_sesv2_dedicated_ip_pool` | имя пула |
| `aws_sesv2_dedicated_ip_assignment` | `<IP-адрес>,<имя_пула>` |
| `aws_sesv2_configuration_set` | имя конфигурации отправки |

Сервисный аккаунт и ключ доступа при этом создаются заново.
