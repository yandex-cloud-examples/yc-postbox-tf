# Пул выделенных IP в Yandex Cloud Postbox

Пример создаёт пул выделенных IP-адресов, перемещает в него выделенные IP-адреса вашего тенанта и создаёт конфигурацию отправки, привязанную к этому пулу. Письма, отправленные с указанием этой конфигурации, уходят только с адресов пула.

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

2. **Каталог, который вы укажете в `folder_id`, принадлежит тому же тенанту Postbox, что и эти адреса.** Пример создаёт в этом каталоге сервисный аккаунт и работает с Postbox от его имени, поэтому пул, привязки адресов и конфигурация отправки появятся в тенанте именно этого каталога. Вывод `yc config get folder-id` доказательством не является: каталог по умолчанию может лежать в том же облаке и даже содержать сервисный аккаунт `postbox-admin-*`, но относиться к другому тенанту Postbox. Убедитесь, что в `folder_id` стоит каталог того тенанта, чьи адреса вы только что увидели в `aws sesv2 get-dedicated-ips`; если сомневаетесь — уточните каталог у владельца тенанта.

3. **Домен для отправки уже подтверждён** — например, примером [EasyDKIM](../EasyDKIM/) или [BYODKIM](../BYODKIM/). Пул сам по себе не даёт права отправлять письма.

4. Установлены [Terraform](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-quickstart) и [AWS CLI](https://yandex.cloud/ru/docs/postbox/tools/aws-cli).

## Применение

1. Заполните `postbox-dedicated-ip-pool.auto.tfvars`:

    ```hcl
    folder_id              = "b1g..."
    pool_name              = "mypool"
    dedicated_ips          = ["203.0.113.10"]
    configuration_set_name = "myconfigset"
    ```

    Пустой список `dedicated_ips` допустим: пул будет создан без адресов. Отправлять через него не получится — см. раздел «Проверка».

2. Задайте учётные данные провайдера Yandex Cloud. Без них `terraform apply` падает ещё до обращения к Postbox с ошибкой `Provider ... requires explicit configuration` — подробнее в разделе [FAQ](../README.md#faq) корневого README:

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

    Фиктивные переменные окружения нужны на этапе `plan`, пока статический ключ доступа ещё не создан. Подробнее — в разделе [FAQ](../README.md#faq) корневого README.

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

## Удаление ресурсов

```bash
export YC_TOKEN=$(yc iam create-token)
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
terraform destroy
```

Удаляются все ресурсы примера — в конфигурации с одним адресом в пуле их шесть, — причём конфигурация отправки и привязки адресов удаляются раньше самого пула:

```text
Destroy complete! Resources: 6 destroyed.
```

Выделенные IP-адреса при этом никуда не деваются: они остаются у тенанта и возвращаются в пул `ses-default-dedicated-pool`. Проверить можно так:

```bash
aws sesv2 get-dedicated-ips \
    --endpoint-url https://postbox.cloud.yandex.net --region ru-central1
```

Сервисный аккаунт `postbox-pools-admin` и его статический ключ доступа удаляются вместе с остальными ресурсами.

## На что обратить внимание

**`apply` падает с `Could not find dedicated IP … under this account` — значит, неверный каталог, а не адрес.** Ошибка называет IP, но причина в другом: сервисный аккаунт создан в каталоге чужого тенанта Postbox, и выделенного адреса в этом тенанте действительно нет.

```text
Error: creating AWS SESv2 (Simple Email V2) Dedicated IP Assignment (31.44.15.41): operation error SESv2: PutDedicatedIpInPool, https response error StatusCode: 404, RequestID: ff98c8ce-0470-4a6b-ac4f-f1064647d7ad, NotFoundException: Could not find dedicated IP 31.44.15.41 under this account.
```

Повторный `apply` не помогает — текст ошибки воспроизводится слово в слово. Перед тем как пробовать другой `folder_id`, выполните `terraform destroy`: сервисный аккаунт, пул и конфигурация отправки к этому моменту уже созданы — успешно, но в чужом тенанте, — и без удаления так там и останутся. Затем проверьте каталог по предусловию 2 и примените конфигурацию заново.

**Имя пула в конфигурации отправки берётся из атрибута ресурса.** В примере написано `sending_pool_name = aws_sesv2_dedicated_ip_pool.example.pool_name`, а не `var.pool_name`. Именно так Terraform понимает, что конфигурация отправки зависит от пула, и при `terraform destroy` удаляет её раньше пула. Если заменить ссылку на переменную, порядок удаления станет произвольным и `destroy` может завершиться ошибкой на пуле, который ещё привязан к конфигурации отправки:

```text
BadRequestException: The dedicated IP pool is in use by a configuration set.
```

Наличие адресов в пуле удалению не мешает: Postbox удаляет непустой пул, а его адреса возвращаются в `ses-default-dedicated-pool`.

**Блок `delivery_options` указывайте всегда.** Конфигурация отправки, объявленная без него, приводит к бесконечному расхождению: Terraform каждый раз показывает удаление блока, а после `apply` `terraform plan` снова оказывается непустым.

**Смена набора адресов в пуле не пересоздаёт пул.** Ключом `for_each` служит сам адрес, поэтому добавление и удаление адресов затрагивает только соответствующие привязки.

**Пул поддерживает теги.** Добавьте в ресурс `aws_sesv2_dedicated_ip_pool` аргумент `tags = { ... }`, если нужно. Их изменение применяется на месте и пул не пересоздаёт.

## Импорт существующих ресурсов

Если пул и конфигурация отправки уже созданы вручную, их можно перенести под управление Terraform. Переменные окружения задайте те же, что и в разделе «Применение»: `YC_TOKEN` и фиктивные ключи AWS.

Сначала создайте сервисный аккаунт, роль и статический ключ доступа: провайдер AWS настраивается по этому ключу, а на чистой копии конфигурации ключа ещё нет, поэтому `terraform import` падает ещё до обращения к Postbox:

```text
Error: Invalid provider configuration

The configuration for provider["registry.terraform.io/hashicorp/aws"] depends
on values that cannot be determined until apply.
```

Ключ создаётся точечным `apply` с `-target`:

```bash
terraform init
terraform apply -target=yandex_iam_service_account_static_access_key.postbox-admin-key \
                -target=yandex_resourcemanager_folder_iam_member.postbox-admin
```

Сервисный аккаунт `postbox-pools-admin` создаётся автоматически — оба указанных ресурса от него зависят, так что `apply` добавляет три ресурса. Предупреждения `Resource targeting is in effect` и `Applied changes may be incomplete` здесь ожидаемы: план намеренно неполный, оставшиеся ресурсы вы добавите импортом. После этого импортируйте существующие ресурсы Postbox:

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

Значения в `postbox-dedicated-ip-pool.auto.tfvars` должны совпадать с именами импортированных ресурсов — тогда `terraform plan` после импорта будет пустым:

```text
No changes. Your infrastructure matches the configuration.
```
