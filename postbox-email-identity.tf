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

variable "domain_signing_selector" {
  type        = string
  default     = "postbox"
  description = "Селектор для подписи домена"
}

variable "domain" {
  type        = string
  description = "Домен, который вы хотите использовать для отправки писем"
}

variable "dns_zone_name" {
  type        = string
  description = "DNS зона, в которую будут добавлены DNS-записи"
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


# Создание Email Identity в Postbox

locals {
  private_key = file("privatekey.pem")
  public_key  = file("dkim_dns_value.txt")
}

resource "aws_sesv2_email_identity" "example" {
  email_identity = var.domain
  dkim_signing_attributes {
    domain_signing_selector    = var.domain_signing_selector
    domain_signing_private_key = local.private_key
  }
  depends_on = [
    yandex_iam_service_account.postbox,
    yandex_iam_service_account_static_access_key.postbox-admin-key,
    yandex_resourcemanager_folder_iam_binding.postbox-admin
  ]
}

# Добавление DNS-записей, если вы используете Yandex Cloud DNS и у вас уже есть DNS-зона

data "yandex_dns_zone" "postbox" {
  name      = var.dns_zone_name
}

# Переменные для форматирования DNS-записи
locals {
  zone = trimsuffix(data.yandex_dns_zone.postbox.zone, ".")
  record_name = trimsuffix(replace(var.domain, local.zone, ""), ".")
  base_record_name = length(local.record_name) > 0 ? ".${local.record_name}" : ""
  dkim             = "\"v=DKIM1;h=sha256;k=rsa;p=${trim(local.public_key, "\n")}\""
}

# Создание DKIM TXT записи в DNS
resource "yandex_dns_recordset" "postbox" {
  name    = "${var.domain_signing_selector}._domainkey"
  zone_id = data.yandex_dns_zone.postbox.id
  type    = "TXT"
  data = [
    local.dkim,
  ]
  ttl = 600
}