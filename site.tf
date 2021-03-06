variable "site_domain" {
    default = "testsiteserver.com"
}

provider "aws" {
    region = "eu-west-2"
}

# Encryption key for bucket contents
resource "aws_kms_key" "bucket_encrypt" {
  description             = "Bucket Encryption Key"
  deletion_window_in_days = 10
}

# Create logs bucket
resource "aws_s3_bucket" "logs" {
    bucket = "${var.site_domain}-logs"
    acl = "log-delivery-write"
}

# Create main site bucket
resource "aws_s3_bucket" "site" {
    bucket = "${var.site_domain}"
    acl = "public-read"

    policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[
        {
        "Sid":"AddPerm",
        "Effect":"Allow",
        "Principal": "*",
        "Action":["s3:GetObject"],
        "Resource":["arn:aws:s3:::${var.site_domain}/*"]
        }
    ]
}
POLICY

    website {
        index_document = "index.html"
    }
    logging {
        target_bucket = "${aws_s3_bucket.logs.id}"
        target_prefix = "log/"
    }

    server_side_encryption_configuration {
        rule {
            apply_server_side_encryption_by_default {
                kms_master_key_id = "${aws_kms_key.bucket_encrypt.arn}"
                sse_algorithm = "aws:kms"
            }
        }
    }
}

# Secondary 'provider' needed as ACM certificates for cloudfront can only be used from us-east-1
provider "aws" {
    alias = "acm-region"
    region = "us-east-1"
}

data "aws_route53_zone" "zone" {
    name = "${var.site_domain}"
    private_zone = false
}

# Request the certificate
resource "aws_acm_certificate" "cert" {
  provider = "aws.acm-region"
  domain_name = "${var.site_domain}"
  subject_alternative_names = ["www.${var.site_domain}"]
  validation_method = "DNS"
}

# Create the two records for certificate validation
resource "aws_route53_record" "cert_validation" {
  name = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.zone.zone_id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl = 60
}

resource "aws_route53_record" "cert_validation_alt" {
  name = "${aws_acm_certificate.cert.domain_validation_options.1.resource_record_name}"
  type = "${aws_acm_certificate.cert.domain_validation_options.1.resource_record_type}"
  zone_id = "${data.aws_route53_zone.zone.zone_id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.1.resource_record_value}"]
  ttl = 60
}

# Validation
resource "aws_acm_certificate_validation" "cert" {
  provider = "aws.acm-region"
  certificate_arn = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}", "${aws_route53_record.cert_validation_alt.fqdn}"]
}

# Now certificate is in place we can create cloudfront
resource "aws_cloudfront_distribution" "cloudfront" {
    origin {
        domain_name = "${aws_s3_bucket.site.bucket_regional_domain_name}"
        origin_id = "${var.site_domain}-origin"
    }

    enabled = true
    is_ipv6_enabled = true
    default_root_object = "index.html"

    aliases = ["${var.site_domain}", "www.${var.site_domain}"]

    default_cache_behavior {
        allowed_methods = ["GET", "HEAD", "OPTIONS"]
        cached_methods = ["GET", "HEAD", "OPTIONS"]
        target_origin_id = "${var.site_domain}-origin"

        # force use of https
        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        # low default_ttl so we can update and see relatively quickly without having to invalidate cache
        default_ttl = 300
        max_ttl = 86400

        forwarded_values {
            query_string = false

            cookies {
                forward = "none"
            }
        }
    }
    
    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    # Use our previosly created cert
    viewer_certificate {
        acm_certificate_arn = "${aws_acm_certificate_validation.cert.certificate_arn}"
        ssl_support_method = "sni-only"
        minimum_protocol_version = "TLSv1.1_2016"
    }
}

# Create A records for both site_domain and www.site_domain
resource "aws_route53_record" "a-record" {
    zone_id = "${data.aws_route53_zone.zone.zone_id}"
    name = "${var.site_domain}"
    type = "A"

    alias {
        name = "${aws_cloudfront_distribution.cloudfront.domain_name}"
        zone_id = "${aws_cloudfront_distribution.cloudfront.hosted_zone_id}"
        evaluate_target_health = false
    }
}

resource "aws_route53_record" "a-record-www" {
    zone_id = "${data.aws_route53_zone.zone.zone_id}"
    name = "www.${var.site_domain}"
    type = "A"

    alias {
        name = "${aws_cloudfront_distribution.cloudfront.domain_name}"
        zone_id = "${aws_cloudfront_distribution.cloudfront.hosted_zone_id}"
        evaluate_target_health = false
    }
}