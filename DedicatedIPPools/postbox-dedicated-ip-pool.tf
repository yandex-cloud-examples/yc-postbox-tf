# Настройка провайдеров

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.89.0"
    }
  }
  required_version = ">= 1.5"
}

provider "aws" {
  secret_key                  = yandex_iam_service_account_static_access_key.postbox-admin-key.secret_key
  access_key                  = yandex_iam_service_account_static_access_key.postbox-admin-key.access_key
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  region                      = "ru-central1"
  endpoints {
    sesv2 = "https://postbox.cloud.yandex.net"
  }
}

# Объявление пользовательских переменных

variable "folder_id" {
  description = "ID каталога, в котором будут созданы ресурсы"
}

variable "pool_name" {
  type        = string
  description = "Имя пула выделенных IP"
}

variable "dedicated_ips" {
  type        = list(string)
  description = "Выделенные IP-адреса, которые нужно поместить в пул. Адреса выдаются вашему тенанту заранее, Terraform их не создаёт"
}

variable "configuration_set_name" {
  type        = string
  description = "Имя конфигурации отправки, привязанной к пулу"
}

# Создание сервисного аккаунта
# Аккаунт называется postbox-pools-admin, а не postbox-admin, чтобы пример можно было
# применить в каталоге, где уже применён пример EasyDKIM или BYODKIM

resource "yandex_iam_service_account" "postbox" {
  name      = "postbox-pools-admin"
  folder_id = var.folder_id
}

# Роль выдаётся ресурсом folder_iam_member, а не folder_iam_binding: binding управляет
# списком всех исполнителей роли целиком, поэтому две конфигурации, выдающие в одном
# каталоге роль postbox.admin, вычёркивали бы сервисные аккаунты друг друга

resource "yandex_resourcemanager_folder_iam_member" "postbox-admin" {
  role      = "postbox.admin"
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.postbox.id}"

  sleep_after = 5
}

resource "yandex_iam_service_account_static_access_key" "postbox-admin-key" {
  service_account_id = yandex_iam_service_account.postbox.id
}

# Создание пула выделенных IP

resource "aws_sesv2_dedicated_ip_pool" "example" {
  pool_name    = var.pool_name
  scaling_mode = "STANDARD"
  depends_on = [
    yandex_iam_service_account.postbox,
    yandex_iam_service_account_static_access_key.postbox-admin-key,
    yandex_resourcemanager_folder_iam_member.postbox-admin
  ]
}

# Перемещение выделенных IP в пул.
# Ключом for_each служит сам адрес, поэтому удаление адреса из середины списка
# не затрагивает остальные привязки

resource "aws_sesv2_dedicated_ip_assignment" "example" {
  for_each              = toset(var.dedicated_ips)
  ip                    = each.value
  destination_pool_name = aws_sesv2_dedicated_ip_pool.example.pool_name
}

# Создание конфигурации отправки, привязанной к пулу.
#
# Имя пула берётся из атрибута ресурса, а не из переменной var.pool_name. Именно
# атрибутная ссылка строит граф зависимостей, из-за которого terraform destroy
# удаляет конфигурацию отправки и привязки IP раньше самого пула

resource "aws_sesv2_configuration_set" "example" {
  configuration_set_name = var.configuration_set_name

  delivery_options {
    sending_pool_name = aws_sesv2_dedicated_ip_pool.example.pool_name
  }
}
