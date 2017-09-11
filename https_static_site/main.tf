variable "main_dns_name"          {
                                    type = "string"
                                  }
variable "alt_dns_names"          {
                                    type = "list"
                                  }
variable "route53_zone_id"        {
                                    type = "string"
                                  }
variable "acm_certificate_arn"    {
                                    description = "ARN of the certificate for TLS cert in us-east-1 region"
                                    type = "string"
                                  }
variable "root_object"            {
                                    default = "index.html"
                                  }
variable "error_object"           {
                                    default = "404.html"
                                  }
variable "cloudfront_price_class" {
                                    description = "One of PriceClass_All, PriceClass_200, PriceClass_100."
                                    default = "PriceClass_All"
                                  }

output "main_bucket"        {
                              value = {
                                website_endpoint = "${aws_s3_bucket.main_bucket.website_endpoint}",
                                arn              = "${aws_s3_bucket.main_bucket.arn}",
                              }
                            }

#--- S3 ----------------------------------------------------------------------
resource "aws_s3_bucket" "main_bucket" {
  bucket = "${var.main_dns_name}"
  website {
    index_document = "${var.root_object}"
    error_document = "404.html"
  }
}

#--- Route53 -----------------------------------------------------------------
resource "aws_route53_record" "main_dns_entry" {
  name    = "${var.main_dns_name}"
  type    = "A"
  zone_id = "${var.route53_zone_id}"

  alias {
    name = "${aws_cloudfront_distribution.cache.domain_name}"
    zone_id = "${aws_cloudfront_distribution.cache.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "redirect_dns_entries" {
  count = "${length(var.alt_dns_names)}"

  name    = "${var.alt_dns_names[count.index]}"
  type    = "A"
  zone_id = "${var.route53_zone_id}"

  alias {
    name = "${aws_cloudfront_distribution.cache.domain_name}"
    zone_id = "${aws_cloudfront_distribution.cache.hosted_zone_id}"
    evaluate_target_health = false
  }
}

# TODO: "access identity" to restrict access to buckets only to CloudFront
#--- Cloudfront --------------------------------------------------------------
resource "aws_cloudfront_distribution" "cache" {
  origin {
    origin_id   = "${replace(var.main_dns_name, ".", "_")}_bucket"
    domain_name = "${aws_s3_bucket.main_bucket.bucket_domain_name}"
  }

  enabled = true
  default_root_object = "${var.root_object}"
  aliases = "${concat(var.alt_dns_names, list(var.main_dns_name))}"

  custom_error_response {
    error_code = 404
    response_code = 404
    response_page_path = "/${var.error_object}"
  }

  price_class = "${var.cloudfront_price_class}"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = "${var.acm_certificate_arn}"
    minimum_protocol_version = "TLSv1"
    ssl_support_method = "sni-only"
  }

  default_cache_behavior {
    allowed_methods  = ["HEAD", "GET", "OPTIONS"]
    cached_methods   = ["HEAD", "GET", "OPTIONS"]
    target_origin_id = "${replace(var.main_dns_name, ".", "_")}_bucket"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
}
