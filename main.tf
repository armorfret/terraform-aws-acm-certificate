terraform {
  required_providers {
    aws = {
      version = "3.4.0"
    }
  }
}

// All hostnames given will be included in the SAN field of the certificate,
// but the ACM API automatically includes the domain_name in the SAN field of the cert,
// and *excludes* it in the response to acm.DescribeCertificate, so we split them here.
locals {
  common_name               = var.hostnames[0]
  subject_alternative_names = slice(var.hostnames, 1, length(var.hostnames))
}

// For generating the DNS records, we convert hostnames into their zone name.
// This makes assumptions about the zone layout
locals {
  host_to_zone_regex = "/^(?:.*\\.)?([^.]+\\.[^.]+)$/"
}

// Sort the validation options into a list
locals {
  validation_list = sort(aws_acm_certificate.this.domain_validation_options)
}

data "aws_route53_zone" "parent" {
  for_each     = toset(var.hostnames)
  name         = replace(each.value, local.host_to_zone_regex, "$1")
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  domain_name               = local.common_name
  subject_alternative_names = local.subject_alternative_names
  validation_method         = "DNS"
}

resource "aws_route53_record" "validation" {
  count = length(var.hostnames)

  zone_id = data.aws_route53_zone.parent[locals.validations_list[count.index]["domain_name"]].id

  name    = locals.validations_list[count.index]["resource_record_name"]
  type    = locals.validations_list[count.index]["resource_record_type"]
  records = [locals.validations_list[count.index]["resource_record_value"]]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = aws_route53_record.validation.*.fqdn
}

