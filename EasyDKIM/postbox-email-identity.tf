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

variable "domain" {
  type        = string
  description = "Домен, который вы хотите использовать для отправки писем"
}

variable "dns_zone_name" {
  type        = string
  description = "Имя зоны DNS, в которую будут добавлены DNS-записи"
}

# Создание сервисного аккаунта

resource "yandex_iam_service_account" "postbox" {
  name      = "postbox-admin"
  folder_id = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_binding" "postbox-admin" {
  for_each = toset([
    "postbox.admin",
  ])
  role      = each.value
  folder_id = var.folder_id
  members = [
    "serviceAccount:${yandex_iam_service_account.postbox.id}",
  ]
  sleep_after = 5
}

resource "yandex_iam_service_account_static_access_key" "postbox-admin-key" {
  service_account_id = yandex_iam_service_account.postbox.id
}

# Создание адреса в Yandex Cloud Postbox с EasyDKIM
# Ключи DKIM генерирует Yandex Cloud Postbox, свой приватный ключ указывать не нужно

resource "aws_sesv2_email_identity" "example" {
  email_identity = var.domain
  depends_on = [
    yandex_iam_service_account.postbox,
    yandex_iam_service_account_static_access_key.postbox-admin-key,
    yandex_resourcemanager_folder_iam_binding.postbox-admin
  ]
}

# Добавление DNS-записей, если вы используете Yandex Cloud DNS и у вас уже есть DNS-зона

data "yandex_dns_zone" "postbox" {
  name      = var.dns_zone_name
  folder_id = var.folder_id
}

# Токены DKIM, которые сгенерировал Yandex Cloud Postbox для EasyDKIM (всегда три штуки)

locals {
  dkim_tokens = aws_sesv2_email_identity.example.dkim_signing_attributes[0].tokens
}

# Создание CNAME-записей DKIM для каждого токена

resource "yandex_dns_recordset" "postbox" {
  count   = 2
  name    = "${local.dkim_tokens[count.index]}._domainkey"
  zone_id = data.yandex_dns_zone.postbox.id
  type    = "CNAME"
  data = [
    "${local.dkim_tokens[count.index]}.dkim.pstbx.ru.",
  ]
  ttl = 600
}
